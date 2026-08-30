// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'PVE Manager';

  @override
  String get addServer => '添加服务器';

  @override
  String get switchLanguage => '切换语言';

  @override
  String get settings => '设置';

  @override
  String get language => '语言';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get autoRefreshInterval => '自动刷新间隔';

  @override
  String get selectAutoRefreshInterval => '选择自动刷新间隔';

  @override
  String secondsInterval(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get checkForUpdatesHint => '从 GitHub 获取最新版本';

  @override
  String get checkingForUpdates => '正在检查更新...';

  @override
  String get upToDate => '已是最新版本';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String currentVersion(Object version) {
    return '当前版本：$version';
  }

  @override
  String latestVersion(Object version) {
    return '最新版本：$version';
  }

  @override
  String get downloadUpdate => '下载更新';

  @override
  String get viewRelease => '查看 Release';

  @override
  String get releaseNotes => '更新说明';

  @override
  String get updateCheckFailed => '检查更新失败，请稍后重试。';

  @override
  String get noReleasePublished => 'GitHub 尚未发布可用版本。';

  @override
  String get updatePlatformUnsupported => '当前平台暂不支持应用更新。';

  @override
  String get updateAssetMissing => '没有找到适用于当前平台的安装包，将打开 Release 页面。';

  @override
  String get updateDownloadFailed => '无法打开更新下载地址。';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get editServer => '编辑服务器';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get add => '添加';

  @override
  String get confirm => '确定';

  @override
  String get verify => '验证';

  @override
  String get enable => '启用';

  @override
  String get disable => '禁用';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get retry => '重试';

  @override
  String get refresh => '刷新';

  @override
  String get back => '返回';

  @override
  String get close => '关闭';

  @override
  String get power => '电源';

  @override
  String get hardwareConfig => '硬件配置';

  @override
  String get configValue => '配置值';

  @override
  String get configSaved => '配置已保存';

  @override
  String get notEditable => '不可修改';

  @override
  String get features => '功能';

  @override
  String get editFeatures => '编辑功能';

  @override
  String get featureKeyctl => '按键';

  @override
  String get featureNesting => '嵌套';

  @override
  String get featureMknod => '创建设备节点';

  @override
  String get experimental => '实验性';

  @override
  String get requiresUnprivilegedContainer => '需要无特权容器';

  @override
  String get bootOrder => '启动项';

  @override
  String get selectBootDevices => '选择启动设备';

  @override
  String get noBootDevices => '未读取到可启动设备';

  @override
  String get onBoot => '开机自启动';

  @override
  String get editCpu => '编辑 CPU';

  @override
  String get cpuType => 'CPU 类型';

  @override
  String get cpuAffinity => 'CPU 亲和性';

  @override
  String get osType => 'OS 类型';

  @override
  String get tags => '标签';

  @override
  String get network => '网络';

  @override
  String get architecture => '架构';

  @override
  String get bridge => '网桥';

  @override
  String get model => '型号';

  @override
  String get vlanTag => 'VLAN 标签';

  @override
  String get firewall => '防火墙';

  @override
  String get disconnected => '断开';

  @override
  String get rateLimit => '速率限制 (MB/s)';

  @override
  String get mtu => 'MTU';

  @override
  String get multiqueue => 'Multiqueue';

  @override
  String get ipAddress => 'IP 地址';

  @override
  String get gateway => '网关';

  @override
  String get macAddress => 'MAC 地址';

  @override
  String get networkName => '名称';

  @override
  String get networkType => '类型';

  @override
  String get cpuUnits => 'CPU 权重';

  @override
  String get editMemory => '编辑内存';

  @override
  String get memoryMib => '内存 (MiB)';

  @override
  String get minimumMemoryMib => '最小内存 (MiB)';

  @override
  String get memoryShares => '共享';

  @override
  String get defaultMemoryShares => '默认 (1000)';

  @override
  String get ballooningDevice => 'Ballooning 设备';

  @override
  String get allowKsm => '允许 KSM';

  @override
  String get machine => '机型';

  @override
  String get display => '显示';

  @override
  String get scsiController => 'SCSI 控制器';

  @override
  String get cpuSockets => 'CPU 插槽';

  @override
  String get defaultValue => '默认';

  @override
  String get terminal => '终端';

  @override
  String get terminalConnecting => '连接中...';

  @override
  String get terminalReconnecting => '正在重连...';

  @override
  String get terminalDisconnected => '连接已关闭';

  @override
  String get terminalAuthenticationFailed => '终端认证失败';

  @override
  String get terminalCopied => '已复制';

  @override
  String get terminalPasted => '已粘贴';

  @override
  String get reconnect => '重连';

  @override
  String get tasksAndLogs => '任务和日志';

  @override
  String get tasks => '任务';

  @override
  String get logs => '日志';

  @override
  String get loadTasks => '加载任务';

  @override
  String get loadLogs => '加载日志';

  @override
  String get loadMore => '加载更多';

  @override
  String get noTasks => '暂无任务';

  @override
  String get noLogs => '暂无日志';

  @override
  String get noData => '暂无数据';

  @override
  String get noServers => '还没有服务器';

  @override
  String get emptyServersHint => '点击右下角加号添加 Proxmox 服务器。';

  @override
  String get serverName => '名称';

  @override
  String get serverNameHint => 'PVE Home';

  @override
  String get proxmoxAddress => 'Proxmox 地址';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get realm => 'Realm';

  @override
  String get authMethod => '认证方式';

  @override
  String get passwordLogin => '密码';

  @override
  String get apiTokenLogin => 'API 令牌';

  @override
  String get apiTokenId => '令牌 ID';

  @override
  String get apiTokenSecret => '令牌密钥';

  @override
  String get allowSelfSignedCertificate => '忽略 TLS 证书错误';

  @override
  String get selfSignedCertificateWarning =>
      '此选项会关闭证书校验，可能导致凭据遭受中间人攻击。仅对确认可信的 PVE 主机启用。';

  @override
  String get twoFactorTitle => '需要二次验证';

  @override
  String get twoFactorCode => '验证码';

  @override
  String get twoFactorCodeHint => 'TOTP；恢复码请输入 recovery:xxxx';

  @override
  String get enterTwoFactorCode => '请输入验证码';

  @override
  String get enterProxmoxAddress => '请输入 Proxmox 地址';

  @override
  String get invalidAddress => '地址格式无效';

  @override
  String get unsupportedScheme => '只支持 http 或 https';

  @override
  String get enterUsername => '请输入用户名';

  @override
  String get enterRealm => '请输入 Realm';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get enterApiTokenId => '请输入令牌 ID';

  @override
  String get enterApiTokenSecret => '请输入令牌密钥';

  @override
  String get apiTokenWebConsoleUnsupported => 'API 令牌不能用于网页 VNC 控制台，请改用密码登录。';

  @override
  String get neverConnected => '从未连接';

  @override
  String lastLogin(Object time) {
    return '上次登录：$time';
  }

  @override
  String get nodes => '节点';

  @override
  String get guests => '虚拟机与容器';

  @override
  String get storage => '存储';

  @override
  String get storageDetails => '存储详情';

  @override
  String get storageOverview => '概要';

  @override
  String get storageBackups => '备份';

  @override
  String get storageVmDisks => 'VM 磁盘';

  @override
  String get storageCtVolumes => 'CT 卷';

  @override
  String get storageIsoImages => 'ISO 镜像';

  @override
  String get storageCtTemplates => 'CT 模板';

  @override
  String get storageSnippets => '配置片段';

  @override
  String get storageImport => '导入';

  @override
  String get storagePermissions => '权限';

  @override
  String get storageStatus => '状态';

  @override
  String get storagePath => '路径';

  @override
  String get storageBackendType => '类型';

  @override
  String get storageCapacity => '容量';

  @override
  String get storageUsed => '已使用';

  @override
  String get storageAvailable => '可用空间';

  @override
  String get storageActive => '活动';

  @override
  String get storageEnabled => '已启用';

  @override
  String get storageShared => '共享';

  @override
  String get storageContent => '内容';

  @override
  String get storageVolume => '卷';

  @override
  String get storageFormat => '格式';

  @override
  String get storageVmid => 'VM/CT ID';

  @override
  String get storageCreatedAt => '创建时间';

  @override
  String get storageNoContent => '此存储中没有对应内容。';

  @override
  String get storageSectionUnsupported => '此分类暂不支持查看。';

  @override
  String nodesCount(int count) {
    return '$count 台';
  }

  @override
  String itemsCount(int count) {
    return '$count 个';
  }

  @override
  String get noNodes => '没有读取到节点。';

  @override
  String get noGuests => '没有读取到虚拟机或容器。';

  @override
  String get noStorage => '没有读取到存储资源。';

  @override
  String get noPermission => '无权限';

  @override
  String get nodeDetails => '节点详情';

  @override
  String get systemInfo => '系统信息';

  @override
  String get resourceUsage => '资源使用情况';

  @override
  String get cpuUsage => 'CPU 使用率';

  @override
  String get memoryHistory => '内存使用率';

  @override
  String totalMemory(Object value) {
    return '(共计 $value)';
  }

  @override
  String get networkIo => '网络 IO';

  @override
  String get diskIo => '磁盘 IO';

  @override
  String get processor => '处理器';

  @override
  String get cpuCores => 'CPU 核心';

  @override
  String cpuCoresValue(int cores, int threads, int sockets) {
    return '$cores核心 $threads线程 $sockets插槽';
  }

  @override
  String get pveVersion => 'PVE 版本';

  @override
  String get kernelVersion => '内核版本';

  @override
  String get uptime => '运行时间';

  @override
  String get loadAverage => '系统负载';

  @override
  String get temperature => '温度';

  @override
  String get cpuFrequencyGhz => 'CPU频率(GHz)';

  @override
  String get cpuTemperature => 'CPU温度';

  @override
  String cpuFrequencyValue(int cores, Object ghz) {
    return '$cores核心 | 平均: $ghz GHz';
  }

  @override
  String cpuFrequencyCurrentValue(Object ghz) {
    return '平均: $ghz GHz';
  }

  @override
  String cpuPackageTemperature(Object temperature) {
    return '封装: $temperature';
  }

  @override
  String cpuCoreTemperature(Object average, Object range) {
    return '核心: 平均 $average ($range)';
  }

  @override
  String temperatureValue(Object temperature) {
    return '温度: $temperature';
  }

  @override
  String nvmeDiskLabel(int index) {
    return 'NVME$index';
  }

  @override
  String sataDiskLabel(int index) {
    return 'SATA$index';
  }

  @override
  String solidStateDiskLabel(int index) {
    return '固态硬盘$index';
  }

  @override
  String get memory => '内存';

  @override
  String get disk => '磁盘';

  @override
  String get swap => '交换分区';

  @override
  String get rootPartition => '根分区';

  @override
  String get capacity => '容量';

  @override
  String get powerActions => '电源操作';

  @override
  String get openVnc => '打开 VNC';

  @override
  String get openTerminal => '打开终端';

  @override
  String get openRemoteVnc => '打开远程 VNC';

  @override
  String get openRemoteTerminal => '打开远程终端';

  @override
  String vncTitle(Object name) {
    return '$name VNC';
  }

  @override
  String terminalTitle(Object name) {
    return '$name 终端';
  }

  @override
  String guestActionSent(Object name, Object action) {
    return '$name 已发送$action请求';
  }

  @override
  String nodePowerConfirm(Object node, Object action) {
    return '确定要对节点 $node 执行$action吗？';
  }

  @override
  String powerRequestSent(Object action) {
    return '已发送$action请求';
  }

  @override
  String get start => '启动';

  @override
  String get shutdown => '关机';

  @override
  String get reboot => '重启';

  @override
  String get stop => '停止';

  @override
  String get rebootNode => '重启节点';

  @override
  String get shutdownNode => '关闭节点';

  @override
  String get online => '在线';

  @override
  String get running => '运行中';

  @override
  String get stopped => '已停止';

  @override
  String get node => '节点';

  @override
  String get storageType => '存储';

  @override
  String get timeframeHour => '1小时';

  @override
  String get timeframeDay => '1天';

  @override
  String get timeframeWeek => '1周';

  @override
  String get timeframeMonth => '1月';

  @override
  String get timeframeYear => '1年';

  @override
  String get onlineNodes => '在线节点';

  @override
  String get runningGuests => '运行实例';

  @override
  String get totalResources => '资源总数';

  @override
  String get webConsoleUnsupported => 'Web 运行模式不支持远程控制台。';

  @override
  String get nativeConsoleMissing =>
      '远程控制台原生模块未加载。请停止当前应用后重新运行，或安装最新构建的 APK；热重启不会加载新增的 Android 原生代码。';

  @override
  String get consoleOpenFailed => '远程控制台打开失败。';

  @override
  String get consoleFallbackTitle => '控制台';

  @override
  String get consoleInvalidArguments => '控制台参数不完整。';

  @override
  String consoleLoadFailed(Object description) {
    return '控制台加载失败：$description';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get consoleCertificateError =>
      '控制台证书校验失败。请信任 PVE 证书，或在服务器配置中启用忽略证书错误。';

  @override
  String get consoleErrorHint => '点击顶部标题返回，或使用系统返回键。';

  @override
  String get platformConsoleUnsupported => '当前平台暂不支持内置远程控制台。';

  @override
  String get socketError => '无法连接到 Proxmox 主机，请检查地址和网络。';

  @override
  String get handshakeError => 'TLS 证书校验失败，可开启自签名证书选项后重试。';

  @override
  String get timeoutError => '请求超时，请检查 Proxmox API 是否可访问。';

  @override
  String get formatError => '接口返回不是有效 JSON，请确认地址指向 Proxmox API。';

  @override
  String get sessionExpired => '会话已失效，请重新登录。';

  @override
  String get guestConsoleOnly => '只能为 VM 或 CT 打开控制台。';

  @override
  String get unsupportedResourceType => '不支持的资源类型。';

  @override
  String get loginResponseInvalid => '登录响应格式异常，请确认地址指向 Proxmox API。';

  @override
  String get loginTicketMissing => '登录响应缺少票据，请检查账号或权限。';

  @override
  String get twoFactorRequired => '该账号需要二次验证。';

  @override
  String get nodeStatusInvalid => '节点状态响应格式异常。';

  @override
  String get terminalSessionInvalid => '终端会话响应格式异常。';

  @override
  String get guestActionOnly => '只能对 VM 或 CT 执行此操作。';

  @override
  String apiFormatInvalid(int statusCode) {
    return '接口返回格式异常：HTTP $statusCode';
  }

  @override
  String requestFailed(int statusCode) {
    return '请求失败：HTTP $statusCode';
  }

  @override
  String redirectResponse(int statusCode, Object location) {
    return 'Proxmox API 返回了重定向：HTTP $statusCode$location。\n请确认地址使用 https://主机:8006，而不是普通网页地址或反向代理跳转地址。';
  }

  @override
  String nonJsonResponse(
    Object uri,
    int statusCode,
    Object contentType,
    Object preview,
    Object hints,
  ) {
    return '接口返回的不是有效 JSON。\n请求：$uri\n状态：HTTP $statusCode\n类型：$contentType\n返回片段：$preview\n$hints';
  }

  @override
  String get nonJsonHintApiAddress =>
      '请确认填写的是 Proxmox API 地址，例如 https://192.168.1.10:8006';

  @override
  String get nonJsonHintHtml =>
      '如果返回片段以 <!doctype html> 或 <html 开头，说明当前连到的是网页或反向代理页面';

  @override
  String get nonJsonHintWeb =>
      '如果你在 Flutter Web 里运行，请改用 Android 或 Windows 运行目标';

  @override
  String get emptyResponsePreview => '<empty>';

  @override
  String durationDaysHoursMinutes(int days, int hours, int minutes) {
    return '$days天$hours小时$minutes分钟';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分钟';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes分钟';
  }
}
