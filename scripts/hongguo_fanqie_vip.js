/**
 * Hongguo & Fanqie Apps VIP Unlock Script
 * Target Apps:
 * - 红果免费短剧 (com.phoenix.video)
 * - 红果小说 (com.phoenix.read)
 * - 番茄免费小说 (com.dragon.read)
 * - 番茄畅听 (com.xs.fm)
 * - 番茄畅听音乐版 (com.fq.music)
 */

function bytesToString(arr) {
    if (typeof arr === 'string') return arr;
    let str = '';
    for (let i = 0; i < arr.length; i++) {
        str += String.fromCharCode(arr[i]);
    }
    try {
        return decodeURIComponent(escape(str));
    } catch (e) {
        return str;
    }
}

let rawBody = $response.body;
if (rawBody) {
    let bodyStr = bytesToString(rawBody);
    try {
        let obj = JSON.parse(bodyStr);
        const EXPIRE_TIME = 2147483647; // 2038-01-19T03:14:07Z
        const LEFT_TIME = 2147483647;

        function modifyVip(target) {
            if (!target || typeof target !== 'object') return;

            // Direct VIP attributes
            if ('is_vip' in target) target.is_vip = 1;
            if ('is_vip_user' in target) target.is_vip_user = 1;
            if ('is_svip' in target) target.is_svip = 1;
            if ('vip_type' in target) target.vip_type = 1;
            if ('vip_status' in target) target.vip_status = 1;
            if ('expire_time' in target) target.expire_time = EXPIRE_TIME;
            if ('left_time' in target) target.left_time = LEFT_TIME;
            if ('left_seconds' in target) target.left_seconds = LEFT_TIME;
            if ('vip_expire_time' in target) target.vip_expire_time = EXPIRE_TIME;
            if ('vip_level' in target) target.vip_level = 1;
            if ('is_in_vip' in target) target.is_in_vip = true;
            if ('has_vip' in target) target.has_vip = true;
            if ('can_read' in target) target.can_read = true;
            if ('can_listen' in target) target.can_listen = true;
            if ('can_watch' in target) target.can_watch = true;

            // Recurse into nested structures
            for (let k in target) {
                if (typeof target[k] === 'object' && target[k] !== null) {
                    if (k === 'vip_info' || k === 'user_vip_info' || k === 'account_info' || k === 'user_info' || k === 'user_extra' || k === 'vip' || k === 'user') {
                        target[k].is_vip = 1;
                        target[k].is_svip = 1;
                        target[k].is_vip_user = 1;
                        target[k].expire_time = EXPIRE_TIME;
                        target[k].left_time = LEFT_TIME;
                        target[k].vip_type = 1;
                        target[k].status = 1;
                        target[k].is_in_vip = true;
                        target[k].vip_title = '尊贵VIP会员';
                    }
                    modifyVip(target[k]);
                }
            }
        }

        modifyVip(obj);

        // Specific handling for common ByteDance reader/drama data structures
        if (obj.data) {
            modifyVip(obj.data);
            if (typeof obj.data === 'object' && !Array.isArray(obj.data)) {
                obj.data.is_vip = 1;
                obj.data.vip_type = 1;
                obj.data.expire_time = EXPIRE_TIME;
                obj.data.left_time = LEFT_TIME;
                obj.data.vip_title = '尊贵VIP会员';
                if (!obj.data.vip_info) {
                    obj.data.vip_info = {
                        is_vip: 1,
                        is_svip: 1,
                        expire_time: EXPIRE_TIME,
                        left_time: LEFT_TIME,
                        vip_type: 1,
                        vip_level: 1,
                        status: 1
                    };
                }
            }
        }

        $done({ body: JSON.stringify(obj) });
    } catch (e) {
        $done({ body: bodyStr });
    }
} else {
    $done({});
}
