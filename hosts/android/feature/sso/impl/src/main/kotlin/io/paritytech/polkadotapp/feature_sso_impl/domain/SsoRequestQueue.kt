package io.paritytech.polkadotapp.feature_sso_impl.domain

import io.paritytech.polkadotapp.feature_sso_impl.domain.session.model.SsoSessionId
import io.paritytech.polkadotapp.feature_sso_impl.domain.session.model.SsoSessionRequest
import io.paritytech.polkadotapp.feature_sso_impl.domain.session.model.SsoSessionRequestId
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch

private const val READ_AHEAD = 64
private const val MAX_EARLY_WITHDRAWALS = 64

// Requests are served one at a time while up to READ_AHEAD more are read, so a Cancel reaches its target
// whether it is being served (cancelled), queued or not received yet (skipped when its turn comes)
class SsoRequestQueue(
    private val serve: suspend (SsoSessionRequest) -> Unit,
    private val onWithdrawn: suspend (SsoSessionRequest) -> Unit,
    private val onCancel: (sessionId: SsoSessionId, messageId: SsoSessionRequestId) -> Unit,
) {
    fun process(requests: Flow<SsoSessionRequest>): Flow<SsoSessionRequest> = channelFlow {
        val withdrawals = Withdrawals()
        val queue = Channel<SsoSessionRequest>(READ_AHEAD)

        launch {
            for (request in queue) {
                val job = withdrawals.startUnlessWithdrawn(RequestKey(request.sessionId, request.requestId)) {
                    launch(start = CoroutineStart.LAZY) { serve(request) }
                }

                job?.join()
                withdrawals.finishServing()

                if (job == null || job.isCancelled) onWithdrawn(request)
                send(request)
            }
        }

        requests.collect { request ->
            when (val content = request.content) {
                is SsoSessionRequest.Content.Cancel -> {
                    withdrawals.withdraw(RequestKey(request.sessionId, content.messageId))
                    onCancel(request.sessionId, content.messageId)
                    send(request)
                }

                else -> queue.send(request)
            }
        }
        queue.close()
    }

    private class Withdrawals {
        private val lock = Any()
        private val withdrawnAhead = LinkedHashSet<RequestKey>()
        private var serving: Serving? = null

        fun startUnlessWithdrawn(key: RequestKey, start: () -> Job): Job? = synchronized(lock) {
            if (withdrawnAhead.remove(key)) null else start().also { serving = Serving(key, it) }
        }

        fun finishServing() = synchronized(lock) {
            serving = null
        }

        fun withdraw(key: RequestKey) = synchronized(lock) {
            val current = serving
            if (current?.key == key) {
                current.job.cancel()
            } else {
                withdrawnAhead.add(key)
                if (withdrawnAhead.size > MAX_EARLY_WITHDRAWALS) {
                    withdrawnAhead.remove(withdrawnAhead.first())
                }
            }
        }
    }

    private data class RequestKey(val sessionId: SsoSessionId, val requestId: SsoSessionRequestId)

    private class Serving(val key: RequestKey, val job: Job)
}
