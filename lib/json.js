/* macOS JXA, no Node.js / Python runtime dependency. */
ObjC.import('Foundation');
function read(path) {
    var error = Ref();
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, error);
    if (!s) throw Error('파일을 읽을 수 없습니다.');
    return ObjC.unwrap(s);
}
function object(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
function keys(v, allowed) {
    if (!object(v)) throw Error('객체 형식이 필요합니다.');
    Object.keys(v).forEach(function(k) { if (allowed.indexOf(k) < 0) throw Error('알 수 없는 설정 키입니다.'); });
}
function bool(v) { if (typeof v !== 'boolean') throw Error('true/false 값이 필요합니다.'); }
function clean(v) {
    var s = String(v === undefined || v === null ? '' : v);
    if (/[\r\n\t|\x00-\x1f]/.test(s)) throw Error('메타데이터에 잘못된 문자가 있습니다.');
    return s;
}
function get(v, path) {
    return path.split('.').reduce(function(a,k) { return a == null ? undefined : a[k]; }, v);
}
function version(v) {
    v = String(v || '').replace(/^v/, '');
    if (!/^[0-9][0-9A-Za-z.,+_\-]*$/.test(v) || /(?:alpha|beta|rc|nightly|preview)/i.test(v)) throw Error('안정 버전을 확인할 수 없습니다.');
    return v;
}
function run(args) {
    var mode = args[0], data, v, lines = [];
    if (mode === 'config') {
        data = JSON.parse(read(args[1]));
        var ids = read(args[2]).split('\n').filter(function(x){return x && x[0] !== '#';}).map(function(x){return x.split('|')[0];});
        keys(data, ['schema_version','defaults','tools','settings','extensions']);
        if (data.schema_version !== 1) throw Error('schema_version은 1이어야 합니다.');
        ['defaults','tools','settings','extensions'].forEach(function(k){
            if (data[k] !== undefined && !object(data[k])) throw Error('설정 섹션은 객체여야 합니다.');
        });
        keys(data.defaults || {}, ['reinstall_on_version_mismatch']);
        var fallback = (data.defaults || {}).reinstall_on_version_mismatch;
        if (fallback === undefined) fallback = false;
        bool(fallback);
        keys(data.tools || {}, ids);
        ids.forEach(function(id) {
            var t = (data.tools || {})[id];
            if (t === undefined) t = {};
            keys(t, ['enabled', 'reinstall_on_version_mismatch']);
            var on = t.enabled === undefined ? false : t.enabled;
            var replace = t.reinstall_on_version_mismatch === undefined ? fallback : t.reinstall_on_version_mismatch;
            bool(on); bool(replace);
            lines.push('tool|' + id + '|' + on + '|' + replace);
        });
        keys(data.settings || {}, ['shell_init']);
        var shell = (data.settings || {}).shell_init;
        if (shell === undefined) shell = true;
        bool(shell); lines.push('shell|' + shell);
        keys(data.extensions || {}, ['vscode','cursor','kiro']);
        Object.keys(data.extensions || {}).forEach(function(ide) {
            var list = data.extensions[ide];
            if (!Array.isArray(list)) throw Error('확장 목록은 배열이어야 합니다.');
            list.forEach(function(id, index) {
                if (typeof id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9-]*$/.test(id)) throw Error('확장 ID 형식이 잘못되었습니다.');
                if (list.indexOf(id) === index) lines.push('extension|' + ide + '|' + id);
            });
        });
        return lines.join('\n');
    }
    data = JSON.parse(read(args[1]));
    if (mode === 'get') {
        v = get(data, args[2]);
        if (v === undefined || v === null) return '';
        return Array.isArray(v) ? v.map(clean).join('\n') : clean(v);
    }
    if (mode === 'release') {
        if (data.draft || data.prerelease) throw Error('안정 릴리스가 아닙니다.');
        return version(data.tag_name);
    }
    if (mode === 'asset') {
        v = (data.assets || []).filter(function(x){ return x.name === args[2]; });
        if (v.length !== 1 || !/^https:\/\//.test(v[0].browser_download_url)) throw Error('배포물이 없습니다.');
        return clean(v[0].browser_download_url) + '|' + clean(v[0].digest || '-');
    }
    if (mode === 'brew') {
        var kind = args[2], tag = args[3];
        if (data.variations && data.variations[tag]) {
            var variation = data.variations[tag];
            Object.keys(variation).forEach(function(k){data[k]=variation[k];});
        }
        if (data.disabled) throw Error('비활성화된 패키지입니다.');
        if (kind === 'formula') {
            var target = version(data.versions.stable);
            if (data.revision) target += '_' + data.revision;
            lines.push('version|' + target);
            var files = get(data, 'bottle.stable.files') || {};
            lines.push('bottle|' + !!(files[tag] || files.all));
            (data.dependencies || []).forEach(function(d){lines.push('dep|' + clean(d));});
        } else {
            lines.push('version|' + version(data.version));
            lines.push('bottle|true');
            (get(data,'depends_on.formula') || []).forEach(function(d){lines.push('dep|' + clean(d));});
            if ((get(data,'depends_on.cask') || []).length) lines.push('unsupported|cask dependency');
            // Refuse scripts and pkg installers whose effects cannot be bounded.
            (data.artifacts || []).forEach(function(a){
                Object.keys(a).forEach(function(k){
                    if (['app','binary','zap','uninstall','target','manpage','qlplugin','mdimporter','colorpicker','prefpane','font','bash_completion','fish_completion','zsh_completion','generate_completions_from_executable'].indexOf(k) < 0)
                        lines.push('unsupported|' + clean(k));
                });
            });
            if (data.supported_platforms && data.supported_platforms.indexOf(tag) < 0) lines.push('unsupported|macOS/ARM64');
            var os = get(data,'depends_on.macos') || {};
            Object.keys(os).forEach(function(op){lines.push('macos|' + clean(op) + '|' + clean([].concat(os[op]).join(',')));});
            if (get(data,'depends_on.arch')) lines.push('arch|' + clean(JSON.stringify(data.depends_on.arch)));
        }
        return lines.join('\n');
    }
    if (mode === 'conda') {
        v = data.filter(function(x){return x.name === 'mamba';});
        return v.length === 1 ? clean(v[0].version) : '';
    }
    if (mode === 'dump') return JSON.stringify(get(data,args[2]), null, 2);
    if (mode === 'cua-release') {
        v = data.filter(function(r){ return !r.draft && /^cua-driver-rs-v[0-9]+\.[0-9]+\.[0-9]+$/.test(r.tag_name); });
        v.sort(function(a,b){
            var x=a.tag_name.replace('cua-driver-rs-v','').split('.').map(Number), y=b.tag_name.replace('cua-driver-rs-v','').split('.').map(Number);
            for(var i=0;i<3;i++) if(x[i]!==y[i]) return y[i]-x[i];
            return 0;
        });
        if (!v.length) throw Error('Cua Driver 안정 릴리스를 찾을 수 없습니다.');
        return JSON.stringify(v[0]);
    }
    if (mode === 'arm-asset') {
        v = (data.assets || []).filter(function(a){return /darwin-arm64\.tar\.gz$/.test(a.name);});
        if (v.length !== 1) throw Error('ARM64 배포물을 찾을 수 없습니다.');
        return clean(v[0].name);
    }
    throw Error('지원하지 않는 JSON 작업입니다.');
}
