/**
 * Hongguo & Fanqie Apps Ad Cleaner Script
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

        const adKeyPatterns = [
            /^ad_/i,
            /_ad$/i,
            /^ad$/i,
            /advertisement/i,
            /splash/i,
            /banner/i,
            /inserted_ad/i,
            /ad_info/i,
            /ad_config/i,
            /ad_cell/i,
            /ad_view/i,
            /interstitial/i,
            /pop_up/i,
            /popup/i,
            /reward_ad/i,
            /unlock_video_ad/i,
            /common_ad/i,
            /read_ad/i
        ];

        function isAdKey(k) {
            return adKeyPatterns.some(pat => pat.test(k));
        }

        function cleanAds(target) {
            if (!target || typeof target !== 'object') return;

            if (Array.isArray(target)) {
                for (let i = target.length - 1; i >= 0; i--) {
                    let item = target[i];
                    if (item && typeof item === 'object') {
                        // Check if array item represents an ad entry
                        if (
                            item.ad_info ||
                            item.ad_data ||
                            item.is_ad === 1 ||
                            item.is_ad === true ||
                            item.cell_type === 'ad' ||
                            item.cell_type === 'feed_ad' ||
                            item.content_type === 'ad' ||
                            (item.type && typeof item.type === 'string' && item.type.toLowerCase().includes('ad'))
                        ) {
                            target.splice(i, 1);
                            continue;
                        }
                        cleanAds(item);
                    }
                }
            } else {
                for (let k in target) {
                    if (isAdKey(k)) {
                        if (typeof target[k] === 'boolean') {
                            target[k] = false;
                        } else if (typeof target[k] === 'number') {
                            target[k] = 0;
                        } else if (Array.isArray(target[k])) {
                            target[k] = [];
                        } else if (typeof target[k] === 'object' && target[k] !== null) {
                            target[k] = {};
                        } else {
                            delete target[k];
                        }
                    } else if (typeof target[k] === 'object' && target[k] !== null) {
                        cleanAds(target[k]);
                    }
                }
            }
        }

        cleanAds(obj);

        // Reader & Video specific settings
        if (obj.data) {
            cleanAds(obj.data);
            if (typeof obj.data === 'object' && !Array.isArray(obj.data)) {
                if ('need_ad' in obj.data) obj.data.need_ad = 0;
                if ('has_ad' in obj.data) obj.data.has_ad = 0;
                if ('ad_free' in obj.data) obj.data.ad_free = 1;
                if ('is_ad_free' in obj.data) obj.data.is_ad_free = 1;
                if ('show_ad' in obj.data) obj.data.show_ad = false;
            }
        }

        $done({ body: JSON.stringify(obj) });
    } catch (e) {
        $done({ body: bodyStr });
    }
} else {
    $done({});
}
