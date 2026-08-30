import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'PVE Manager'**
  String get appTitle;

  /// No description provided for @addServer.
  ///
  /// In zh, this message translates to:
  /// **'添加服务器'**
  String get addServer;

  /// No description provided for @switchLanguage.
  ///
  /// In zh, this message translates to:
  /// **'切换语言'**
  String get switchLanguage;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In zh, this message translates to:
  /// **'选择语言'**
  String get selectLanguage;

  /// No description provided for @autoRefreshInterval.
  ///
  /// In zh, this message translates to:
  /// **'自动刷新间隔'**
  String get autoRefreshInterval;

  /// No description provided for @selectAutoRefreshInterval.
  ///
  /// In zh, this message translates to:
  /// **'选择自动刷新间隔'**
  String get selectAutoRefreshInterval;

  /// No description provided for @secondsInterval.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String secondsInterval(int seconds);

  /// No description provided for @languageChineseSimplified.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageChineseSimplified;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @editServer.
  ///
  /// In zh, this message translates to:
  /// **'编辑服务器'**
  String get editServer;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get add;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @verify.
  ///
  /// In zh, this message translates to:
  /// **'验证'**
  String get verify;

  /// No description provided for @enable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In zh, this message translates to:
  /// **'禁用'**
  String get disable;

  /// No description provided for @yes.
  ///
  /// In zh, this message translates to:
  /// **'是'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In zh, this message translates to:
  /// **'否'**
  String get no;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @power.
  ///
  /// In zh, this message translates to:
  /// **'电源'**
  String get power;

  /// No description provided for @hardwareConfig.
  ///
  /// In zh, this message translates to:
  /// **'硬件配置'**
  String get hardwareConfig;

  /// No description provided for @configValue.
  ///
  /// In zh, this message translates to:
  /// **'配置值'**
  String get configValue;

  /// No description provided for @configSaved.
  ///
  /// In zh, this message translates to:
  /// **'配置已保存'**
  String get configSaved;

  /// No description provided for @notEditable.
  ///
  /// In zh, this message translates to:
  /// **'不可修改'**
  String get notEditable;

  /// No description provided for @features.
  ///
  /// In zh, this message translates to:
  /// **'功能'**
  String get features;

  /// No description provided for @editFeatures.
  ///
  /// In zh, this message translates to:
  /// **'编辑功能'**
  String get editFeatures;

  /// No description provided for @featureKeyctl.
  ///
  /// In zh, this message translates to:
  /// **'按键'**
  String get featureKeyctl;

  /// No description provided for @featureNesting.
  ///
  /// In zh, this message translates to:
  /// **'嵌套'**
  String get featureNesting;

  /// No description provided for @featureMknod.
  ///
  /// In zh, this message translates to:
  /// **'创建设备节点'**
  String get featureMknod;

  /// No description provided for @experimental.
  ///
  /// In zh, this message translates to:
  /// **'实验性'**
  String get experimental;

  /// No description provided for @requiresUnprivilegedContainer.
  ///
  /// In zh, this message translates to:
  /// **'需要无特权容器'**
  String get requiresUnprivilegedContainer;

  /// No description provided for @bootOrder.
  ///
  /// In zh, this message translates to:
  /// **'启动项'**
  String get bootOrder;

  /// No description provided for @selectBootDevices.
  ///
  /// In zh, this message translates to:
  /// **'选择启动设备'**
  String get selectBootDevices;

  /// No description provided for @noBootDevices.
  ///
  /// In zh, this message translates to:
  /// **'未读取到可启动设备'**
  String get noBootDevices;

  /// No description provided for @onBoot.
  ///
  /// In zh, this message translates to:
  /// **'开机自启动'**
  String get onBoot;

  /// No description provided for @editCpu.
  ///
  /// In zh, this message translates to:
  /// **'编辑 CPU'**
  String get editCpu;

  /// No description provided for @cpuType.
  ///
  /// In zh, this message translates to:
  /// **'CPU 类型'**
  String get cpuType;

  /// No description provided for @cpuAffinity.
  ///
  /// In zh, this message translates to:
  /// **'CPU 亲和性'**
  String get cpuAffinity;

  /// No description provided for @osType.
  ///
  /// In zh, this message translates to:
  /// **'OS 类型'**
  String get osType;

  /// No description provided for @tags.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get tags;

  /// No description provided for @network.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get network;

  /// No description provided for @architecture.
  ///
  /// In zh, this message translates to:
  /// **'架构'**
  String get architecture;

  /// No description provided for @bridge.
  ///
  /// In zh, this message translates to:
  /// **'网桥'**
  String get bridge;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'型号'**
  String get model;

  /// No description provided for @vlanTag.
  ///
  /// In zh, this message translates to:
  /// **'VLAN 标签'**
  String get vlanTag;

  /// No description provided for @firewall.
  ///
  /// In zh, this message translates to:
  /// **'防火墙'**
  String get firewall;

  /// No description provided for @disconnected.
  ///
  /// In zh, this message translates to:
  /// **'断开'**
  String get disconnected;

  /// No description provided for @rateLimit.
  ///
  /// In zh, this message translates to:
  /// **'速率限制 (MB/s)'**
  String get rateLimit;

  /// No description provided for @mtu.
  ///
  /// In zh, this message translates to:
  /// **'MTU'**
  String get mtu;

  /// No description provided for @multiqueue.
  ///
  /// In zh, this message translates to:
  /// **'Multiqueue'**
  String get multiqueue;

  /// No description provided for @ipAddress.
  ///
  /// In zh, this message translates to:
  /// **'IP 地址'**
  String get ipAddress;

  /// No description provided for @gateway.
  ///
  /// In zh, this message translates to:
  /// **'网关'**
  String get gateway;

  /// No description provided for @macAddress.
  ///
  /// In zh, this message translates to:
  /// **'MAC 地址'**
  String get macAddress;

  /// No description provided for @networkName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get networkName;

  /// No description provided for @networkType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get networkType;

  /// No description provided for @cpuUnits.
  ///
  /// In zh, this message translates to:
  /// **'CPU 权重'**
  String get cpuUnits;

  /// No description provided for @editMemory.
  ///
  /// In zh, this message translates to:
  /// **'编辑内存'**
  String get editMemory;

  /// No description provided for @memoryMib.
  ///
  /// In zh, this message translates to:
  /// **'内存 (MiB)'**
  String get memoryMib;

  /// No description provided for @minimumMemoryMib.
  ///
  /// In zh, this message translates to:
  /// **'最小内存 (MiB)'**
  String get minimumMemoryMib;

  /// No description provided for @memoryShares.
  ///
  /// In zh, this message translates to:
  /// **'共享'**
  String get memoryShares;

  /// No description provided for @defaultMemoryShares.
  ///
  /// In zh, this message translates to:
  /// **'默认 (1000)'**
  String get defaultMemoryShares;

  /// No description provided for @ballooningDevice.
  ///
  /// In zh, this message translates to:
  /// **'Ballooning 设备'**
  String get ballooningDevice;

  /// No description provided for @allowKsm.
  ///
  /// In zh, this message translates to:
  /// **'允许 KSM'**
  String get allowKsm;

  /// No description provided for @machine.
  ///
  /// In zh, this message translates to:
  /// **'机型'**
  String get machine;

  /// No description provided for @display.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get display;

  /// No description provided for @scsiController.
  ///
  /// In zh, this message translates to:
  /// **'SCSI 控制器'**
  String get scsiController;

  /// No description provided for @cpuSockets.
  ///
  /// In zh, this message translates to:
  /// **'CPU 插槽'**
  String get cpuSockets;

  /// No description provided for @defaultValue.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get defaultValue;

  /// No description provided for @terminal.
  ///
  /// In zh, this message translates to:
  /// **'终端'**
  String get terminal;

  /// No description provided for @terminalConnecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中...'**
  String get terminalConnecting;

  /// No description provided for @terminalReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在重连...'**
  String get terminalReconnecting;

  /// No description provided for @terminalDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'连接已关闭'**
  String get terminalDisconnected;

  /// No description provided for @terminalAuthenticationFailed.
  ///
  /// In zh, this message translates to:
  /// **'终端认证失败'**
  String get terminalAuthenticationFailed;

  /// No description provided for @terminalCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get terminalCopied;

  /// No description provided for @terminalPasted.
  ///
  /// In zh, this message translates to:
  /// **'已粘贴'**
  String get terminalPasted;

  /// No description provided for @reconnect.
  ///
  /// In zh, this message translates to:
  /// **'重连'**
  String get reconnect;

  /// No description provided for @tasksAndLogs.
  ///
  /// In zh, this message translates to:
  /// **'任务和日志'**
  String get tasksAndLogs;

  /// No description provided for @tasks.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get tasks;

  /// No description provided for @logs.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get logs;

  /// No description provided for @loadTasks.
  ///
  /// In zh, this message translates to:
  /// **'加载任务'**
  String get loadTasks;

  /// No description provided for @loadLogs.
  ///
  /// In zh, this message translates to:
  /// **'加载日志'**
  String get loadLogs;

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get loadMore;

  /// No description provided for @noTasks.
  ///
  /// In zh, this message translates to:
  /// **'暂无任务'**
  String get noTasks;

  /// No description provided for @noLogs.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogs;

  /// No description provided for @noData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get noData;

  /// No description provided for @noServers.
  ///
  /// In zh, this message translates to:
  /// **'还没有服务器'**
  String get noServers;

  /// No description provided for @emptyServersHint.
  ///
  /// In zh, this message translates to:
  /// **'点击右下角加号添加 Proxmox 服务器。'**
  String get emptyServersHint;

  /// No description provided for @serverName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get serverName;

  /// No description provided for @serverNameHint.
  ///
  /// In zh, this message translates to:
  /// **'PVE Home'**
  String get serverNameHint;

  /// No description provided for @proxmoxAddress.
  ///
  /// In zh, this message translates to:
  /// **'Proxmox 地址'**
  String get proxmoxAddress;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @realm.
  ///
  /// In zh, this message translates to:
  /// **'Realm'**
  String get realm;

  /// No description provided for @authMethod.
  ///
  /// In zh, this message translates to:
  /// **'认证方式'**
  String get authMethod;

  /// No description provided for @passwordLogin.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get passwordLogin;

  /// No description provided for @apiTokenLogin.
  ///
  /// In zh, this message translates to:
  /// **'API 令牌'**
  String get apiTokenLogin;

  /// No description provided for @apiTokenId.
  ///
  /// In zh, this message translates to:
  /// **'令牌 ID'**
  String get apiTokenId;

  /// No description provided for @apiTokenSecret.
  ///
  /// In zh, this message translates to:
  /// **'令牌密钥'**
  String get apiTokenSecret;

  /// No description provided for @allowSelfSignedCertificate.
  ///
  /// In zh, this message translates to:
  /// **'允许自签名证书'**
  String get allowSelfSignedCertificate;

  /// No description provided for @twoFactorTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要二次验证'**
  String get twoFactorTitle;

  /// No description provided for @twoFactorCode.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get twoFactorCode;

  /// No description provided for @twoFactorCodeHint.
  ///
  /// In zh, this message translates to:
  /// **'TOTP；恢复码请输入 recovery:xxxx'**
  String get twoFactorCodeHint;

  /// No description provided for @enterTwoFactorCode.
  ///
  /// In zh, this message translates to:
  /// **'请输入验证码'**
  String get enterTwoFactorCode;

  /// No description provided for @enterProxmoxAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入 Proxmox 地址'**
  String get enterProxmoxAddress;

  /// No description provided for @invalidAddress.
  ///
  /// In zh, this message translates to:
  /// **'地址格式无效'**
  String get invalidAddress;

  /// No description provided for @unsupportedScheme.
  ///
  /// In zh, this message translates to:
  /// **'只支持 http 或 https'**
  String get unsupportedScheme;

  /// No description provided for @enterUsername.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get enterUsername;

  /// No description provided for @enterRealm.
  ///
  /// In zh, this message translates to:
  /// **'请输入 Realm'**
  String get enterRealm;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get enterPassword;

  /// No description provided for @enterApiTokenId.
  ///
  /// In zh, this message translates to:
  /// **'请输入令牌 ID'**
  String get enterApiTokenId;

  /// No description provided for @enterApiTokenSecret.
  ///
  /// In zh, this message translates to:
  /// **'请输入令牌密钥'**
  String get enterApiTokenSecret;

  /// No description provided for @apiTokenWebConsoleUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'API 令牌不能用于网页 VNC 控制台，请改用密码登录。'**
  String get apiTokenWebConsoleUnsupported;

  /// No description provided for @neverConnected.
  ///
  /// In zh, this message translates to:
  /// **'从未连接'**
  String get neverConnected;

  /// No description provided for @lastLogin.
  ///
  /// In zh, this message translates to:
  /// **'上次登录：{time}'**
  String lastLogin(Object time);

  /// No description provided for @nodes.
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get nodes;

  /// No description provided for @guests.
  ///
  /// In zh, this message translates to:
  /// **'虚拟机与容器'**
  String get guests;

  /// No description provided for @storage.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get storage;

  /// No description provided for @nodesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台'**
  String nodesCount(int count);

  /// No description provided for @itemsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String itemsCount(int count);

  /// No description provided for @noNodes.
  ///
  /// In zh, this message translates to:
  /// **'没有读取到节点。'**
  String get noNodes;

  /// No description provided for @noGuests.
  ///
  /// In zh, this message translates to:
  /// **'没有读取到虚拟机或容器。'**
  String get noGuests;

  /// No description provided for @noStorage.
  ///
  /// In zh, this message translates to:
  /// **'没有读取到存储资源。'**
  String get noStorage;

  /// No description provided for @noPermission.
  ///
  /// In zh, this message translates to:
  /// **'无权限'**
  String get noPermission;

  /// No description provided for @nodeDetails.
  ///
  /// In zh, this message translates to:
  /// **'节点详情'**
  String get nodeDetails;

  /// No description provided for @systemInfo.
  ///
  /// In zh, this message translates to:
  /// **'系统信息'**
  String get systemInfo;

  /// No description provided for @resourceUsage.
  ///
  /// In zh, this message translates to:
  /// **'资源使用情况'**
  String get resourceUsage;

  /// No description provided for @cpuUsage.
  ///
  /// In zh, this message translates to:
  /// **'CPU 使用率'**
  String get cpuUsage;

  /// No description provided for @memoryHistory.
  ///
  /// In zh, this message translates to:
  /// **'内存使用率'**
  String get memoryHistory;

  /// No description provided for @totalMemory.
  ///
  /// In zh, this message translates to:
  /// **'(共计 {value})'**
  String totalMemory(Object value);

  /// No description provided for @networkIo.
  ///
  /// In zh, this message translates to:
  /// **'网络 IO'**
  String get networkIo;

  /// No description provided for @diskIo.
  ///
  /// In zh, this message translates to:
  /// **'磁盘 IO'**
  String get diskIo;

  /// No description provided for @processor.
  ///
  /// In zh, this message translates to:
  /// **'处理器'**
  String get processor;

  /// No description provided for @cpuCores.
  ///
  /// In zh, this message translates to:
  /// **'CPU 核心'**
  String get cpuCores;

  /// No description provided for @cpuCoresValue.
  ///
  /// In zh, this message translates to:
  /// **'{cores}核心 {threads}线程 {sockets}插槽'**
  String cpuCoresValue(int cores, int threads, int sockets);

  /// No description provided for @pveVersion.
  ///
  /// In zh, this message translates to:
  /// **'PVE 版本'**
  String get pveVersion;

  /// No description provided for @kernelVersion.
  ///
  /// In zh, this message translates to:
  /// **'内核版本'**
  String get kernelVersion;

  /// No description provided for @uptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时间'**
  String get uptime;

  /// No description provided for @loadAverage.
  ///
  /// In zh, this message translates to:
  /// **'系统负载'**
  String get loadAverage;

  /// No description provided for @temperature.
  ///
  /// In zh, this message translates to:
  /// **'温度'**
  String get temperature;

  /// No description provided for @cpuFrequencyGhz.
  ///
  /// In zh, this message translates to:
  /// **'CPU频率(GHz)'**
  String get cpuFrequencyGhz;

  /// No description provided for @cpuTemperature.
  ///
  /// In zh, this message translates to:
  /// **'CPU温度'**
  String get cpuTemperature;

  /// No description provided for @cpuFrequencyValue.
  ///
  /// In zh, this message translates to:
  /// **'{cores}核心 | 平均: {ghz} GHz'**
  String cpuFrequencyValue(int cores, Object ghz);

  /// No description provided for @cpuFrequencyCurrentValue.
  ///
  /// In zh, this message translates to:
  /// **'平均: {ghz} GHz'**
  String cpuFrequencyCurrentValue(Object ghz);

  /// No description provided for @cpuPackageTemperature.
  ///
  /// In zh, this message translates to:
  /// **'封装: {temperature}'**
  String cpuPackageTemperature(Object temperature);

  /// No description provided for @cpuCoreTemperature.
  ///
  /// In zh, this message translates to:
  /// **'核心: 平均 {average} ({range})'**
  String cpuCoreTemperature(Object average, Object range);

  /// No description provided for @temperatureValue.
  ///
  /// In zh, this message translates to:
  /// **'温度: {temperature}'**
  String temperatureValue(Object temperature);

  /// No description provided for @nvmeDiskLabel.
  ///
  /// In zh, this message translates to:
  /// **'NVME{index}'**
  String nvmeDiskLabel(int index);

  /// No description provided for @sataDiskLabel.
  ///
  /// In zh, this message translates to:
  /// **'SATA{index}'**
  String sataDiskLabel(int index);

  /// No description provided for @solidStateDiskLabel.
  ///
  /// In zh, this message translates to:
  /// **'固态硬盘{index}'**
  String solidStateDiskLabel(int index);

  /// No description provided for @memory.
  ///
  /// In zh, this message translates to:
  /// **'内存'**
  String get memory;

  /// No description provided for @disk.
  ///
  /// In zh, this message translates to:
  /// **'磁盘'**
  String get disk;

  /// No description provided for @swap.
  ///
  /// In zh, this message translates to:
  /// **'交换分区'**
  String get swap;

  /// No description provided for @rootPartition.
  ///
  /// In zh, this message translates to:
  /// **'根分区'**
  String get rootPartition;

  /// No description provided for @capacity.
  ///
  /// In zh, this message translates to:
  /// **'容量'**
  String get capacity;

  /// No description provided for @powerActions.
  ///
  /// In zh, this message translates to:
  /// **'电源操作'**
  String get powerActions;

  /// No description provided for @openVnc.
  ///
  /// In zh, this message translates to:
  /// **'打开 VNC'**
  String get openVnc;

  /// No description provided for @openTerminal.
  ///
  /// In zh, this message translates to:
  /// **'打开终端'**
  String get openTerminal;

  /// No description provided for @openRemoteVnc.
  ///
  /// In zh, this message translates to:
  /// **'打开远程 VNC'**
  String get openRemoteVnc;

  /// No description provided for @openRemoteTerminal.
  ///
  /// In zh, this message translates to:
  /// **'打开远程终端'**
  String get openRemoteTerminal;

  /// No description provided for @vncTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} VNC'**
  String vncTitle(Object name);

  /// No description provided for @terminalTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} 终端'**
  String terminalTitle(Object name);

  /// No description provided for @guestActionSent.
  ///
  /// In zh, this message translates to:
  /// **'{name} 已发送{action}请求'**
  String guestActionSent(Object name, Object action);

  /// No description provided for @nodePowerConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要对节点 {node} 执行{action}吗？'**
  String nodePowerConfirm(Object node, Object action);

  /// No description provided for @powerRequestSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送{action}请求'**
  String powerRequestSent(Object action);

  /// No description provided for @start.
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get start;

  /// No description provided for @shutdown.
  ///
  /// In zh, this message translates to:
  /// **'关机'**
  String get shutdown;

  /// No description provided for @reboot.
  ///
  /// In zh, this message translates to:
  /// **'重启'**
  String get reboot;

  /// No description provided for @stop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @rebootNode.
  ///
  /// In zh, this message translates to:
  /// **'重启节点'**
  String get rebootNode;

  /// No description provided for @shutdownNode.
  ///
  /// In zh, this message translates to:
  /// **'关闭节点'**
  String get shutdownNode;

  /// No description provided for @online.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get online;

  /// No description provided for @running.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get running;

  /// No description provided for @stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stopped;

  /// No description provided for @node.
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get node;

  /// No description provided for @storageType.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get storageType;

  /// No description provided for @timeframeHour.
  ///
  /// In zh, this message translates to:
  /// **'1小时'**
  String get timeframeHour;

  /// No description provided for @timeframeDay.
  ///
  /// In zh, this message translates to:
  /// **'1天'**
  String get timeframeDay;

  /// No description provided for @timeframeWeek.
  ///
  /// In zh, this message translates to:
  /// **'1周'**
  String get timeframeWeek;

  /// No description provided for @timeframeMonth.
  ///
  /// In zh, this message translates to:
  /// **'1月'**
  String get timeframeMonth;

  /// No description provided for @timeframeYear.
  ///
  /// In zh, this message translates to:
  /// **'1年'**
  String get timeframeYear;

  /// No description provided for @onlineNodes.
  ///
  /// In zh, this message translates to:
  /// **'在线节点'**
  String get onlineNodes;

  /// No description provided for @runningGuests.
  ///
  /// In zh, this message translates to:
  /// **'运行实例'**
  String get runningGuests;

  /// No description provided for @totalResources.
  ///
  /// In zh, this message translates to:
  /// **'资源总数'**
  String get totalResources;

  /// No description provided for @webConsoleUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'Web 运行模式不支持远程控制台。'**
  String get webConsoleUnsupported;

  /// No description provided for @nativeConsoleMissing.
  ///
  /// In zh, this message translates to:
  /// **'远程控制台原生模块未加载。请停止当前应用后重新运行，或安装最新构建的 APK；热重启不会加载新增的 Android 原生代码。'**
  String get nativeConsoleMissing;

  /// No description provided for @consoleOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'远程控制台打开失败。'**
  String get consoleOpenFailed;

  /// No description provided for @consoleFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'控制台'**
  String get consoleFallbackTitle;

  /// No description provided for @consoleInvalidArguments.
  ///
  /// In zh, this message translates to:
  /// **'控制台参数不完整。'**
  String get consoleInvalidArguments;

  /// No description provided for @consoleLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'控制台加载失败：{description}'**
  String consoleLoadFailed(Object description);

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get unknownError;

  /// No description provided for @consoleCertificateError.
  ///
  /// In zh, this message translates to:
  /// **'控制台证书校验失败。请信任 PVE 证书，或在服务器配置中启用忽略证书错误。'**
  String get consoleCertificateError;

  /// No description provided for @consoleErrorHint.
  ///
  /// In zh, this message translates to:
  /// **'点击顶部标题返回，或使用系统返回键。'**
  String get consoleErrorHint;

  /// No description provided for @platformConsoleUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持内置远程控制台。'**
  String get platformConsoleUnsupported;

  /// No description provided for @socketError.
  ///
  /// In zh, this message translates to:
  /// **'无法连接到 Proxmox 主机，请检查地址和网络。'**
  String get socketError;

  /// No description provided for @handshakeError.
  ///
  /// In zh, this message translates to:
  /// **'TLS 证书校验失败，可开启自签名证书选项后重试。'**
  String get handshakeError;

  /// No description provided for @timeoutError.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请检查 Proxmox API 是否可访问。'**
  String get timeoutError;

  /// No description provided for @formatError.
  ///
  /// In zh, this message translates to:
  /// **'接口返回不是有效 JSON，请确认地址指向 Proxmox API。'**
  String get formatError;

  /// No description provided for @sessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'会话已失效，请重新登录。'**
  String get sessionExpired;

  /// No description provided for @guestConsoleOnly.
  ///
  /// In zh, this message translates to:
  /// **'只能为 VM 或 CT 打开控制台。'**
  String get guestConsoleOnly;

  /// No description provided for @unsupportedResourceType.
  ///
  /// In zh, this message translates to:
  /// **'不支持的资源类型。'**
  String get unsupportedResourceType;

  /// No description provided for @loginResponseInvalid.
  ///
  /// In zh, this message translates to:
  /// **'登录响应格式异常，请确认地址指向 Proxmox API。'**
  String get loginResponseInvalid;

  /// No description provided for @loginTicketMissing.
  ///
  /// In zh, this message translates to:
  /// **'登录响应缺少票据，请检查账号或权限。'**
  String get loginTicketMissing;

  /// No description provided for @twoFactorRequired.
  ///
  /// In zh, this message translates to:
  /// **'该账号需要二次验证。'**
  String get twoFactorRequired;

  /// No description provided for @nodeStatusInvalid.
  ///
  /// In zh, this message translates to:
  /// **'节点状态响应格式异常。'**
  String get nodeStatusInvalid;

  /// No description provided for @terminalSessionInvalid.
  ///
  /// In zh, this message translates to:
  /// **'终端会话响应格式异常。'**
  String get terminalSessionInvalid;

  /// No description provided for @guestActionOnly.
  ///
  /// In zh, this message translates to:
  /// **'只能对 VM 或 CT 执行此操作。'**
  String get guestActionOnly;

  /// No description provided for @apiFormatInvalid.
  ///
  /// In zh, this message translates to:
  /// **'接口返回格式异常：HTTP {statusCode}'**
  String apiFormatInvalid(int statusCode);

  /// No description provided for @requestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败：HTTP {statusCode}'**
  String requestFailed(int statusCode);

  /// No description provided for @redirectResponse.
  ///
  /// In zh, this message translates to:
  /// **'Proxmox API 返回了重定向：HTTP {statusCode}{location}。\n请确认地址使用 https://主机:8006，而不是普通网页地址或反向代理跳转地址。'**
  String redirectResponse(int statusCode, Object location);

  /// No description provided for @nonJsonResponse.
  ///
  /// In zh, this message translates to:
  /// **'接口返回的不是有效 JSON。\n请求：{uri}\n状态：HTTP {statusCode}\n类型：{contentType}\n返回片段：{preview}\n{hints}'**
  String nonJsonResponse(
    Object uri,
    int statusCode,
    Object contentType,
    Object preview,
    Object hints,
  );

  /// No description provided for @nonJsonHintApiAddress.
  ///
  /// In zh, this message translates to:
  /// **'请确认填写的是 Proxmox API 地址，例如 https://192.168.1.10:8006'**
  String get nonJsonHintApiAddress;

  /// No description provided for @nonJsonHintHtml.
  ///
  /// In zh, this message translates to:
  /// **'如果返回片段以 <!doctype html> 或 <html 开头，说明当前连到的是网页或反向代理页面'**
  String get nonJsonHintHtml;

  /// No description provided for @nonJsonHintWeb.
  ///
  /// In zh, this message translates to:
  /// **'如果你在 Flutter Web 里运行，请改用 Android 或 Windows 运行目标'**
  String get nonJsonHintWeb;

  /// No description provided for @emptyResponsePreview.
  ///
  /// In zh, this message translates to:
  /// **'<empty>'**
  String get emptyResponsePreview;

  /// No description provided for @durationDaysHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{days}天{hours}小时{minutes}分钟'**
  String durationDaysHoursMinutes(int days, int hours, int minutes);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours}小时{minutes}分钟'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes}分钟'**
  String durationMinutes(int minutes);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
