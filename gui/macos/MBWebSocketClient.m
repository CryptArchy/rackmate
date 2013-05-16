#import "AppDelegate.h"
#import "AsyncSocket.h"
#import <Security/SecRandom.h>

size_t base64_size(size_t length);
size_t base64(const char *inputBuffer, size_t inputBufferSize, char *outputBuffer, size_t outputBufferSize);

static unsigned long long ntohll(unsigned long long v) {
    union { unsigned long lv[2]; unsigned long long llv; } u;
    u.llv = v;
    return ((unsigned long long)ntohl(u.lv[0]) << 32) | (unsigned long long)ntohl(u.lv[1]);
}


@implementation MBWebSocketClient {
    AsyncSocket *socket;
    AsyncSocket *connection;
}

- (id)init {
    socket = [[AsyncSocket alloc] initWithDelegate:self];
    [self connect];
    return self;
}

- (void)connect {
    [socket connectToHost:@"localhost" onPort:13581 error:nil]; //TODO:ERROR
}

- (void)send:(NSData *)o {
    if ([o isKindOfClass:[NSString class]]) o = [(NSString *)o dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *data = [NSMutableData dataWithLength:10];
    char *header = data.mutableBytes;
    header[0] = 0x81;
    if (o.length > 65535) {
        header[1] = 127;
        header[2] = (o.length >> 56) & 255;
        header[3] = (o.length >> 48) & 255;
        header[4] = (o.length >> 40) & 255;
        header[5] = (o.length >> 32) & 255;
        header[6] = (o.length >> 24) & 255;
        header[7] = (o.length >> 16) & 255;
        header[8] = (o.length >>  8) & 255;
        header[9] = o.length & 255;
    } else if (o.length > 125) {
        header[1] = 126;
        header[2] = (o.length >> 8) & 255;
        header[3] = o.length & 255;
        data.length = 4;
    } else {
        header[1] = o.length;
        data.length = 2;
    }
    header[1] |= 0x80; //set masked bit

    const char *input = o.bytes;
    char *out = data.mutableBytes + data.length;
    [data increaseLengthBy:o.length + 4];

    const uint32_t mask = rand();
    out[0] = (char)((mask >> 24) & 0xFF);
    out[1] = (char)((mask >> 16) & 0xFF);
    out[2] = (char)((mask >> 8) & 0XFF);
    out[3] = (char)((mask & 0XFF));
    for (int i = 0; i < o.length; ++i)
        out[i + 4] = input[i] ^ out[i % 4];

    [socket writeData:data withTimeout:-1 tag:2];
}

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    uint8_t in[16];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(in), in);
    int n = base64_size(sizeof(in));
    char out[n];
    n = base64((char *)in, sizeof(in), out, n);

    id upgrade = [NSString stringWithFormat:@"GET / HTTP/1.1\r\n"
             "Host: localhost:13581\r\n"
             "Upgrade: websocket\r\n"
             "Connection: Upgrade\r\n"
             "Sec-WebSocket-Key: %.*s\r\n"
             "Sec-WebSocket-Protocol: rackmate\r\n"
             "Sec-WebSocket-Version: 13\r\n\r\n", n, out];

    [sock writeData:[upgrade dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:1];
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    @try {
        const unsigned char *bytes = data.bytes;
        switch (tag) {
            case 1:
                [sock readDataToLength:2 withTimeout:-1 tag:2];
                break;
            case 2: {
                uint64_t const N = bytes[1] & 0x7f;
                char const opcode = bytes[0] & 0x0f;
                if (N >= 126)
                    [sock readDataToLength:N == 126 ? 2 : 8 withTimeout:-1 tag:3];
                else
                    [sock readDataToLength:N withTimeout:-1 tag:4];
                break;
            }
            case 3: { // figure out payload length
                uint64_t N;
                if (data.length == 2) {
                    uint16_t *p = (uint16_t *)bytes;
                    N = ntohs(*p);
                } else {
                    uint64_t *p = (uint64_t *)bytes;
                    N = ntohll(*p);
                }
                [sock readDataToLength:N withTimeout:-1 tag:4];
                break;
            }
            case 4: // read complete payload
                [[NSApp delegate] performSelector:@selector(webSocketData:) withObject:data];
                [sock readDataToLength:2 withTimeout:-1 tag:2];
                break;
        }
    } @catch (id e) {
        //TODO:ERROR
        [sock disconnect];
    }
}

- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (tag == 1) {
        id sep = [NSData dataWithBytes:"\r\n\r\n" length:4];
        [sock readDataToData:sep withTimeout:-1 tag:1];
    }
}

/**
 * In the event of an error, the socket is closed.
 * You may call "unreadData" during this call-back to get the last bit of data off the socket.
 * When connecting, this delegate method may be called
 * before"onSocket:didAcceptNewSocket:" or "onSocket:didConnectToHost:".
 **/
- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err {
    //TODO:ERROR
    NSLog(@"%@", err);
    if (sock == socket)
        [self performSelector:@selector(connect) withObject:nil afterDelay:1];
}

/**
 * Called when a socket disconnects with or without error.  If you want to release a socket after it disconnects,
 * do so here. It is not safe to do that during "onSocket:willDisconnectWithError:".
 **/
- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{}

@end
