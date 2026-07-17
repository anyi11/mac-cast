/**
 * Surge JavaScript for YouTube Adblock
 * Optimized for high performance and low memory consumption.
 */

const url = $request.url;
let headers = $response.headers || {};
const contentType = headers['Content-Type'] || headers['content-type'] || '';

// 移除 Alt-Svc 头部，防止升级到 HTTP/3 QUIC
if (headers['Alt-Svc']) delete headers['Alt-Svc'];
if (headers['alt-svc']) delete headers['alt-svc'];

// 极速且节省内存的分块转译函数 (利用数组 join 减少临时 String 内存分配与 GC 压力)
function bytesToString(arr) {
    if (typeof arr === 'string') return arr;
    let parts = [];
    const chunk = 16384; // 16K 分块大小
    for (let i = 0; i < arr.length; i += chunk) {
        parts.push(String.fromCharCode.apply(null, arr.subarray(i, i + chunk)));
    }
    let str = parts.join('');
    try {
        return decodeURIComponent(escape(str));
    } catch (e) {
        return str;
    }
}

if (url.indexOf('/youtubei/v1/player') !== -1) {
    if (contentType.indexOf('application/json') !== -1) {
        // A. JSON 格式处理 (Chrome / Safari 浏览器端)
        try {
            let bodyStr = bytesToString($response.body);
            let body = JSON.parse(bodyStr);
            
            // 递归清理 adPlacements 和 adSlots 字段
            function cleanJson(obj) {
                if (typeof obj === 'object' && obj !== null) {
                    if (obj.hasOwnProperty('adPlacements')) {
                        delete obj['adPlacements'];
                    }
                    if (obj.hasOwnProperty('adSlots')) {
                        delete obj['adSlots'];
                    }
                    for (let key in obj) {
                        cleanJson(obj[key]);
                    }
                } else if (Array.isArray(obj)) {
                    obj.forEach(cleanJson);
                }
            }
            cleanJson(body);
            $done({ headers, body: JSON.stringify(body) });
        } catch (e) {
            console.log('[YouTube-Adblock] Failed to parse JSON: ' + e);
            $done({ headers });
        }
    } else if (contentType.indexOf('x-protobuf') !== -1 || contentType.indexOf('octet-stream') !== -1) {
        // B. Protobuf 二进制格式处理 (iOS/Android App 端)
        try {
            let rawBody = $response.body; // Uint8Array
            if (rawBody) {
                let modifiedBody = stripProtobufAds(rawBody);
                $done({ headers, body: modifiedBody });
            } else {
                $done({ headers });
            }
        } catch (e) {
            console.log('[YouTube-Adblock] Failed to parse Protobuf: ' + e);
            $done({ headers });
        }
    } else {
        $done({ headers });
    }
} else {
    $done({ headers });
}

// --- Protobuf 核心处理辅助函数 ---
function stripProtobufAds(buffer) {
    let offset = 0;
    let output = [];
    
    while (offset < buffer.length) {
        let start = offset;
        let { tag, wireType, nextOffset } = readKey(buffer, offset);
        offset = nextOffset;
        
        let valueStart = offset;
        offset = skipField(buffer, offset, wireType);
        let valueEnd = offset;
        
        if (tag === 7 && wireType === 2) {
            let subBuffer = buffer.subarray(valueStart, valueEnd);
            let cleanedSubBuffer = stripProtobufAds(subBuffer);
            
            let tagVarint = makeKey(7, 2);
            let lengthVarint = makeVarint(cleanedSubBuffer.length);
            output.push(...tagVarint, ...lengthVarint, ...cleanedSubBuffer);
        }
        else if (tag !== 12 && tag !== 13) {
            let fieldSlice = buffer.subarray(start, valueEnd);
            output.push(...fieldSlice);
        } else {
            console.log('[YouTube-Adblock] Stripped Protobuf Tag: ' + tag);
        }
    }
    return new Uint8Array(output);
}

function readKey(buffer, offset) {
    let { val, offset: nextOffset } = readVarint(buffer, offset);
    let wireType = val & 0x07;
    let tag = val >> 3;
    return { tag, wireType, nextOffset };
}

function readVarint(buffer, offset) {
    let val = 0;
    let shift = 0;
    while (true) {
        let b = buffer[offset++];
        val |= (b & 0x7F) << shift;
        if (!(b & 0x80)) break;
        shift += 7;
    }
    return { val, offset };
}

function makeKey(tag, wireType) {
    return makeVarint((tag << 3) | wireType);
}

function makeVarint(value) {
    let bytes = [];
    while (value >= 0x80) {
        bytes.push((value & 0x7F) | 0x80);
        value >>>= 7;
    }
    bytes.push(value);
    return bytes;
}

function skipField(buffer, offset, wireType) {
    if (wireType === 0) {
        while (buffer[offset++] & 0x80) {}
    } else if (wireType === 1) {
        offset += 8;
    } else if (wireType === 2) {
        let { val: len, offset: nextOffset } = readVarint(buffer, offset);
        offset = nextOffset + len;
    } else if (wireType === 5) {
        offset += 4;
    } else {
        throw new Error('Unsupported wire type: ' + wireType);
    }
    return offset;
}
