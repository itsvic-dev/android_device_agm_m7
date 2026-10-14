/*
 * Copyright (C) 2025 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#define FAILURE_DEBUG_PREFIX "AtChannel"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <string>
#include <unistd.h>

#include "AtChannel.h"
#include "debug.h"
#include "ratUtils.h"

namespace aidl {
namespace android {
namespace hardware {
namespace radio {
namespace implementation {
namespace {
int sendRequestImpl(const int fd, const char* data, size_t size) {
    while (size > 0) {
        const ssize_t written = ::write(fd, data, size);
        if (written >= 0) {
            data += written;
            size -= written;
        } else if (errno == EINTR) {
            continue;
        } else {
            return FAILURE(errno);
        }
    }

    return 0;
}
}  // namespace

#undef FAILURE_DEBUG_PREFIX
#define FAILURE_DEBUG_PREFIX "AtChannel::RequestPipe"

bool AtChannel::RequestPipe::operator()(const std::string_view request) const {
    int err = sendRequestImpl(mFd, request.data(), request.size());
    if (err == 0) {
        const char kCR = 0x0D;
        err = sendRequestImpl(mFd, &kCR, 1);
    }

    return err == 0;
}

#undef FAILURE_DEBUG_PREFIX
#define FAILURE_DEBUG_PREFIX "AtChannel"

AtChannel::AtChannel(HostChannelFactory hostChannelFactory,
                     InitSequence initSequence)
        : mHostChannelFactory(std::move(hostChannelFactory))
        , mInitSequence(std::move(initSequence)) {
    mRequestThread = std::thread(&AtChannel::requestLoop, this);
}

AtChannel::~AtChannel() {
    queueRequester({});
    mRequestThread.join();
    mReaderThread.join();
}

void AtChannel::queueRequester(Requester requester) {
    std::lock_guard<std::mutex> lock(mRequestQueueMtx);
    mRequesterQueue.push_back(std::move(requester));
    mRequesterAvailable.notify_one();
}

void AtChannel::addResponseSink(ResponseSink responseSink) {
    std::lock_guard<std::mutex> lock(mResponseSinksMtx);
    mResponseSinks.push_back(std::move(responseSink));
}

namespace {
// A request that the modem rejected fails, but the channel still works.
std::atomic<bool> gRequestRejected{false};
}  // namespace

void AtChannel::requestLoop() {
    while (true) {
        const Requester requester = getRequester();
        if (requester) {
            gRequestRejected = false;
            if (!requester(getHostChannelPipe()) && !gRequestRejected) {
                resetHostChannel();
            }
        } else {
            break;
        }
    }

    resetHostChannel();
}

void AtChannel::readingLoop(const int hostChannelFd) {
    std::vector<char> unconsumed;
    while (receiveResponses(hostChannelFd, &unconsumed)) {}
}

AtChannel::Requester AtChannel::getRequester() {
    std::unique_lock<std::mutex> lock(mRequestQueueMtx);
    while (true) {
        if (!mRequesterQueue.empty()) {
            Requester requester(std::move(mRequesterQueue.front()));
            mRequesterQueue.pop_front();
            return requester;
        } else {
            mRequesterAvailable.wait(lock);
        }
    }
}

void AtChannel::broadcastResponse(const AtResponsePtr& response) {
    mConversation.send(response);

    std::lock_guard<std::mutex> lock(mResponseSinksMtx);

    const auto newEnd = std::remove_if(mResponseSinks.begin(), mResponseSinks.end(),
        [&response](const ResponseSink& responseSink) -> bool {
            return !responseSink(response);
        });

    mResponseSinks.erase(newEnd, mResponseSinks.end());
}

void AtChannel::resetHostChannel(unique_fd fd) {
    std::lock_guard<std::mutex> lock(mHostChannelMtx);
    mHostChannel = std::move(fd);
}

int AtChannel::getHostChannelFd() const {
    std::lock_guard<std::mutex> lock(mHostChannelMtx);
    return mHostChannel.get();
}

AtChannel::RequestPipe AtChannel::getHostChannelPipe() {
    int hostChannelFd = getHostChannelFd();
    if (hostChannelFd < 0) {
        if (mReaderThread.joinable()) {
            mReaderThread.join();
        }

        unique_fd newHostChannel = mHostChannelFactory();
        if (!newHostChannel.ok()) {
            return RequestPipe(FAILURE_V(-1, "%s", "mHostChannelFactory failed"));
        }

        hostChannelFd = newHostChannel.get();
        resetHostChannel(std::move(newHostChannel));

        mReaderThread = std::thread([this, hostChannelFd](){
            readingLoop(hostChannelFd);
            resetHostChannel();
        });

        LOG_ALWAYS_FATAL_IF(!mInitSequence(RequestPipe(hostChannelFd), mConversation),
                            "%s:%d: Can't init the host channel", __func__, __LINE__);
    }

    return RequestPipe(hostChannelFd);
}

namespace {
// The MediaTek modem ends lines with CR LF, the parser expects CR only.
int dropLineFeeds(char* const buf, const int len) {
    return std::remove(buf, buf + len, '\n') - buf;
}
}  // namespace

bool AtChannel::receiveResponses(const int hostChannelFd,
                                 std::vector<char>* unconsumed) {
    const size_t unconsumedSize = unconsumed->size();
    if (unconsumedSize == 0) {
        char buf[128];
        int len = ::read(hostChannelFd, buf, sizeof(buf));
        if (len > 0) {
            len = dropLineFeeds(buf, len);
            return receiveResponsesImpl(buf, buf + len, unconsumed);
        } else if (len < 0) {
            const int err = errno;
            if (err == EINTR) {
                return true;
            } else {
                return FAILURE_V(false, "fd=%d, err=%s (%d)",
                                 hostChannelFd, ::strerror(err), err);
            }
        }
    } else {
        const size_t newSize = std::max(unconsumedSize + 1024, unconsumed->capacity());
        unconsumed->resize(newSize);
        int len = ::read(hostChannelFd, &(*unconsumed)[unconsumedSize],
                         newSize - unconsumedSize);
        if (len > 0) {
            len = dropLineFeeds(&(*unconsumed)[unconsumedSize], len);
            unconsumed->resize(unconsumedSize + len);
            char* begin = unconsumed->data();
            char* end = begin + unconsumedSize + len;
            return receiveResponsesImpl(begin, end, unconsumed);
        } else if (len < 0) {
            const int err = errno;
            if (err == EINTR) {
                return true;
            } else {
                return FAILURE_V(false, "fd=%d, err=%s (%d)",
                                 hostChannelFd, ::strerror(err), err);
            }
        }
    }

    return true;
}

// NOTE: [begin, end) could contain one or more requests,
// the last one might be incomplete
bool AtChannel::receiveResponsesImpl(const char* begin, const char* const end,
                                     std::vector<char>* unconsumed) {
    while (begin < end) {
        const char* next = receiveOneResponse(begin, end);
        if (next == begin) {
            unconsumed->assign(begin, end);
            return true;
        } else if (next == nullptr) {
            RLOGE("Can't parse '%*.*s'", int(end - begin), int(end - begin), begin);
            return false;
        } else {
            begin = next;
        }
    }

    unconsumed->clear();
    return true;
}

const char* AtChannel::receiveOneResponse(const char* const begin, const char* const end) {
    switch (*begin) {
    case '\r':
    case '\n':
        return begin + 1;
    }

    auto [consumed, response] = AtResponse::parse(std::string_view(begin, end - begin));
    if (response) {
        broadcastResponse(response);
    }

    return (consumed >= 0) ? (begin + consumed) : nullptr;
}

namespace {
// AT+CTEC is a command of the emulator modem. The MediaTek modem reports its
// technology in the <AcT> of +CREG/+CGREG/+CEREG, and +ERAT=6,4 already allows
// GSM, WCDMA and LTE, so the HAL answers +CTEC itself.
AtResponsePtr emulateCtec(const std::string_view request) {
    using ratUtils::ModemTechnology;
    AtResponse::CTEC ctec;

    if (request == "AT+CTEC=?") {
        for (const ModemTechnology t : { ModemTechnology::GSM, ModemTechnology::WCDMA,
                                         ModemTechnology::LTE }) {
            ctec.values.push_back(std::to_string(static_cast<int>(t)));
        }
    } else if (request == "AT+CTEC?") {
        ModemTechnology t;
        switch (lastRegisteredAccessTechnology()) {
        case 2: case 4: case 5: case 6: t = ModemTechnology::WCDMA; break;
        case 7: t = ModemTechnology::LTE; break;
        default: t = ModemTechnology::GSM; break;
        }
        ctec.values.push_back(std::to_string(1 << static_cast<int>(t)));
    } else {
        ctec.values.push_back("DONE");
    }

    return AtResponse::make(std::move(ctec));
}
}  // namespace

AtResponsePtr AtChannel::Conversation::operator()(
        const RequestPipe requestPipe,
        const std::string_view request,
        const AtChannel::Conversation::FilterFunc& filter,
        const AtChannel::Conversation::Duration timeout) {
    if (request.starts_with("AT+CTEC")) {
        return emulateCtec(request);
    }

    std::future<AtResponsePtr> futureResponse;

    {
        std::lock_guard<std::mutex> lock(mMtx);
        mFilter = &filter;
        mSink = decltype(mSink)();
        futureResponse = mSink.get_future();
    }

    if (!requestPipe(request)) {
        std::lock_guard<std::mutex> lock(mMtx);
        mFilter = nullptr;
        return nullptr;
    } else if (futureResponse.wait_for(timeout) == std::future_status::ready) {
        return futureResponse.get();
    } else {
        {
            std::lock_guard<std::mutex> lock(mMtx);
            mFilter = nullptr;
        }

        const int requestLen = request.size();
        return FAILURE_V(nullptr, "Timeout for '%*.*s'",
                         requestLen, requestLen, request.data());
    }
}

AtResponsePtr AtChannel::Conversation::operator()(
        const RequestPipe requestPipe,
        const std::string_view request,
        const FilterFunc& filter) {
    using namespace std::chrono_literals;
    return (*this)(requestPipe, request, filter, 3s);
}

bool AtChannel::Conversation::send(const AtResponsePtr& response) {
    std::lock_guard<std::mutex> lock(mMtx);
    if (!mFilter) {
        return false;
    }

    AtResponsePtr delivered;
    if ((*mFilter)(*response)) {
        delivered = response;
    } else if (response->isERROR() || response->holds<AtResponse::CmeError>()) {
        // MediaTek answers unsupported commands with a plain ERROR. Fail the request now
        // instead of after a timeout, as a CME error if the request accepts one.
        AtResponsePtr cmeError = response;
        if (response->isERROR()) {
            cmeError = AtResponse::make(AtResponse::CmeError{
                    .error = RadioError::REQUEST_NOT_SUPPORTED,
            });
        }
        if ((*mFilter)(*cmeError)) {
            delivered = std::move(cmeError);
        } else {
            RLOGW("%s: the modem rejected the request", __func__);
            gRequestRejected = true;
        }
    } else {
        return false;
    }

    mFilter = nullptr;
    mSink.set_value(std::move(delivered));
    return true;
}

}  // namespace implementation
}  // namespace radio
}  // namespace hardware
}  // namespace android
}  // namespace aidl
