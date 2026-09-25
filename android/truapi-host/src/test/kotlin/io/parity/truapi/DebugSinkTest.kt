package io.parity.truapi

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import uniffi.truapi.HostDevicePermissionRequest
import uniffi.truapi.HostFeatureSupportedRequest
import uniffi.truapi.RemotePermission
import uniffi.truapi_platform.PermissionDecision
import uniffi.truapi_server.NativeDebugSink
import uniffi.truapi_server.NativeDebugSinkException

class DebugSinkTest {
    /** A sink installed from Kotlin sees both directions of a bridged request, as a loopback debugger receives them. */
    @Test(timeout = 60_000)
    fun installedSinkForwardsBridgedFramesToTheDebugger() {
        LoopbackDebugger().use { debugger ->
            val bridge = StubHostBridge()
            TrUAPIHostRuntime(
                bridge,
                HostRuntimeConfig(
                    hostName = "truapi-host-tests",
                    peopleChainGenesisHash = ByteArray(32),
                    bulletinChainGenesisHash = ByteArray(32),
                    assetHubChainGenesisHash = ByteArray(32) { 1 },
                    networkSuffix = "paseo",
                ),
            ).use { runtime ->
                runtime.openProductExecution(bridge, ProductExecutionConfig("test.dot", ProductExecutionKind.APP)).use { execution ->
                    execution.setDebugSink(NativeDebugSink.connect("ws://127.0.0.1:${debugger.port}"))
                    val endpoint = execution.startWsBridge()

                    val request = featureSupportedRequestFrame()
                    val response = roundTrip(endpoint.port.toInt(), endpoint.token, request)

                    val out = debugger.nextEnvelope()
                    val back = debugger.nextEnvelope()
                    assertNotNull("installed sink never reached the debugger", out)
                    assertNotNull("debugger saw only one direction", back)
                    val encoder = Base64.getEncoder()
                    val channelId = out!!.field("channelId")
                    assertTrue("unexpected channel id $channelId", channelId!!.startsWith("test.dot#"))
                    assertEquals("out", out.field("dir"))
                    assertEquals(encoder.encodeToString(request), out.field("frame"))
                    assertEquals(channelId, back!!.field("channelId"))
                    assertEquals("in", back.field("dir"))
                    assertEquals(encoder.encodeToString(response), back.field("frame"))
                    execution.stopWsBridge()
                }
            }
        }
    }

    @Test
    fun sinkRefusesARoutableTarget() {
        try {
            NativeDebugSink.connect("ws://192.0.2.1:9231")
            fail("a routable debug url must be refused")
        } catch (refused: NativeDebugSinkException.NotLoopback) {
            // Expected.
        }
    }

    // wire_table.rs: SYSTEM_FEATURE_SUPPORTED { trait_id: 1, method_id: 1 }.
    private fun featureSupportedRequestFrame(): ByteArray =
        byteArrayOf(0x0C) + // compact length 3
            "p:1".toByteArray() +
            byteArrayOf(0x01, 0x01) +
            // message_type=Request(0x00), then the payload: V1(0x00), Chain(0x00), compact(32) (0x80).
            byteArrayOf(0x00, 0x00, 0x00, 0x80.toByte()) +
            ByteArray(32)

    /** Sends one binary frame as the product and returns the first binary frame the bridge answers with. */
    private fun roundTrip(port: Int, token: String, request: ByteArray): ByteArray =
        Socket(InetAddress.getLoopbackAddress(), port).use { socket ->
            socket.soTimeout = 10_000
            val key = Base64.getEncoder().encodeToString(ByteArray(16) { it.toByte() })
            val output = socket.getOutputStream()
            output.write(
                "GET /?t=$token HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n\r\n"
                    .toByteArray(),
            )
            output.flush()
            val input = DataInputStream(socket.getInputStream())
            val status = readHeaders(input).firstOrNull()
            check(status?.contains(" 101 ") == true) { "bridge refused the upgrade: $status" }
            // A client frame is masked; an all-zero mask leaves the payload as is.
            val header = ByteArrayOutputStream().apply {
                write(0x82)
                when {
                    request.size < 126 -> write(0x80 or request.size)
                    else -> {
                        write(0x80 or 126)
                        write(request.size shr 8)
                        write(request.size and 0xFF)
                    }
                }
                write(ByteArray(4))
            }
            output.write(header.toByteArray() + request)
            output.flush()
            generateSequence { readFrame(input) }.first { (opcode, _) -> opcode == 0x2 }.second
        }
}

private fun String.field(name: String): String? = Regex("\"$name\":\"([^\"]*)\"").find(this)?.groupValues?.get(1)

/**
 * Stands in for `@parity/truapi-debugger`'s WebSocket server on loopback: accepts one client and
 * queues every text message it sends. Android's unit-test classpath has no WebSocket server.
 */
private class LoopbackDebugger : AutoCloseable {
    private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
    private val received = LinkedBlockingQueue<String>()
    val port: Int = server.localPort

    init {
        Thread({ serve() }, "loopback-debugger").apply { isDaemon = true }.start()
    }

    fun nextEnvelope(): String? = received.poll(10, TimeUnit.SECONDS)

    override fun close() {
        server.close()
    }

    private fun serve() {
        runCatching {
            server.accept().use { client ->
                val input = DataInputStream(client.getInputStream())
                val key =
                    readHeaders(input)
                        .firstNotNullOf { Regex("(?i)^Sec-WebSocket-Key:\\s*(.+)$").find(it)?.groupValues?.get(1)?.trim() }
                val accept =
                    Base64.getEncoder().encodeToString(
                        MessageDigest.getInstance("SHA-1").digest((key + WEBSOCKET_GUID).toByteArray()),
                    )
                client.getOutputStream().apply {
                    write(
                        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n"
                            .toByteArray(),
                    )
                    flush()
                }
                while (true) {
                    val (opcode, payload) = readFrame(input)
                    when (opcode) {
                        0x1 -> received.put(String(payload))
                        0x8 -> return@use
                    }
                }
            }
        }
    }

    private companion object {
        const val WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    }
}

/** Reads an HTTP head up to its blank line. */
private fun readHeaders(input: InputStream): List<String> {
    val lines = mutableListOf<String>()
    val line = StringBuilder()
    while (true) {
        val byte = input.read()
        if (byte < 0) return lines
        if (byte == '\n'.code) {
            val text = line.toString().trimEnd('\r')
            if (text.isEmpty()) return lines
            lines += text
            line.clear()
        } else {
            line.append(byte.toChar())
        }
    }
}

/** Reads one unfragmented WebSocket frame, unmasking it if masked. */
private fun readFrame(input: DataInputStream): Pair<Int, ByteArray> {
    val head = input.readUnsignedByte()
    val lengthByte = input.readUnsignedByte()
    val length =
        when (val short = lengthByte and 0x7F) {
            126 -> input.readUnsignedShort().toLong()
            127 -> input.readLong()
            else -> short.toLong()
        }
    val masked = lengthByte and 0x80 != 0
    val mask = ByteArray(4).also { if (masked) input.readFully(it) }
    val payload = ByteArray(length.toInt()).also { input.readFully(it) }
    if (masked) payload.indices.forEach { payload[it] = (payload[it].toInt() xor mask[it % 4].toInt()).toByte() }
    return (head and 0x0F) to payload
}

private class StubHostBridge : HostBridge {
    override val storage: HostStorage =
        object : HostStorage {
            private val store = mutableMapOf<String, ByteArray>()

            override fun read(key: String): ByteArray? = synchronized(store) { store[key] }

            override fun write(key: String, value: ByteArray) {
                synchronized(store) { store[key] = value }
            }

            override fun clear(key: String) {
                synchronized(store) { store.remove(key) }
            }
        }

    override val coreStorage: HostCoreStorage =
        object : HostCoreStorage {
            private val store = mutableMapOf<String, ByteArray>()

            override fun read(key: ByteArray): ByteArray? = synchronized(store) { store[key.contentToString()] }

            override fun write(key: ByteArray, value: ByteArray) {
                synchronized(store) { store[key.contentToString()] = value }
            }

            override fun clear(key: ByteArray) {
                synchronized(store) { store.remove(key.contentToString()) }
            }
        }

    override suspend fun navigateTo(url: String) {}

    override suspend fun devicePermission(
        product: ProductExecutionConfig,
        request: HostDevicePermissionRequest,
    ): PermissionDecision = PermissionDecision.DENY

    override suspend fun remotePermission(
        product: ProductExecutionConfig,
        request: RemotePermission,
    ): PermissionDecision = PermissionDecision.DENY

    override suspend fun featureSupported(request: HostFeatureSupportedRequest): Boolean = true
}
