import 'xrk_glyphs.dart';

/// 图标词汇:**Phosphor Regular**(1.5 描边、圆端、几何),选中 / 点亮 / 开启态用同一
/// 骨架的 **Fill**。规范见 `docs/design/polish-guide.md` §1。
///
/// - 按**角色**命名,不按图形命名:同一个图形可以担几个角色(`regenerate` 和 `refresh`
///   都是顺时针箭头),一个角色只有一个图形。业务代码只写 `AppIcons.xxx`,不写
///   `Icons.*`,也不写 `XrkGlyphs.*`。换图形改这里一行;换整套只重生成 [XrkGlyphs]。
/// - 字形来自自建子集字体 `assets/fonts/XrkIcons.ttf`。Phosphor 在网格里留白比
///   Material 多,字体里已统一放大 10%,所以同一个 `size:` 和 Material 图标占同样
///   的格子、同样的视觉大小。颜色和尺寸走 `IconTheme` / `XrkColors`。
/// - 新增角色:在下面加一行 `static const foo = XrkGlyphs.barBaz;`(Phosphor 名的
///   驼峰,`…Fill` 取 Fill),然后在 `app/` 下运行 `python3 tool/make_icon_font.py`。
abstract final class AppIcons {
  // ── 导航与外壳 ──────────────────────────────────────────────
  static const back = XrkGlyphs.arrowLeft;
  static const forward = XrkGlyphs.arrowRight;
  static const close = XrkGlyphs.x;
  static const menu = XrkGlyphs.list;
  static const more = XrkGlyphs.dotsThree;

  /// 系统「⋮」菜单(只在引导里指给用户看)。
  static const moreVertical = XrkGlyphs.dotsThreeVertical;

  /// 行尾「进入」、面包屑分隔。
  static const disclosure = XrkGlyphs.caretRight;
  static const expand = XrkGlyphs.caretDown;
  static const collapse = XrkGlyphs.caretUp;

  /// 可切换的选择器:主机、工作区、余额。
  static const dropdown = XrkGlyphs.caretUpDown;
  static const openExternal = XrkGlyphs.arrowSquareOut;
  static const openLink = XrkGlyphs.arrowUpRight;
  static const openWith = XrkGlyphs.dotsNine;
  static const allFeatures = XrkGlyphs.dotsNine;
  static const browser = XrkGlyphs.browser;
  static const scrollToBottom = XrkGlyphs.arrowDown;
  static const sidebar = XrkGlyphs.sidebarSimpleRight;
  static const dragHandle = XrkGlyphs.dotsSixVertical;
  static const swap = XrkGlyphs.arrowsLeftRight;

  /// 终端方向键、补全面板里的回车提示。
  static const keyUp = XrkGlyphs.caretUp;
  static const keyDown = XrkGlyphs.caretDown;
  static const keyLeft = XrkGlyphs.caretLeft;
  static const keyRight = XrkGlyphs.caretRight;
  static const enterKey = XrkGlyphs.arrowElbowDownLeft;

  /// 翻页(插件轮播):上一页 / 下一页。上一页在从右往左的语言里要镜像着画。
  static const pagePrevious = XrkGlyphs.caretLeft;
  static const pageNext = XrkGlyphs.caretRight;

  // ── 输入框 ──────────────────────────────────────────────────
  static const send = XrkGlyphs.arrowUp;

  /// 输入框圆键里的停止(生成、语音):实心方块。
  static const stopGenerating = XrkGlyphs.stopFill;
  static const voice = XrkGlyphs.microphone;

  /// 插话:本轮中途送进去。
  static const steer = XrkGlyphs.arrowElbowDownRight;

  /// 排队:本轮结束后发送。
  static const queued = XrkGlyphs.clock;

  /// 打断:停掉本轮再发。
  static const interrupt = XrkGlyphs.stopCircle;
  static const camera = XrkGlyphs.camera;
  static const gallery = XrkGlyphs.images;
  static const files = XrkGlyphs.folderOpen;
  static const addImage = XrkGlyphs.image;

  /// 「传文件到电脑」 (Remote workspace upload).
  static const uploadToHost = XrkGlyphs.boxArrowUp;

  // ── 消息操作 ────────────────────────────────────────────────
  static const copy = XrkGlyphs.copy;
  static const quote = XrkGlyphs.quotes;
  static const share = XrkGlyphs.export;
  static const qrCode = XrkGlyphs.qrCode;
  static const shareImage = XrkGlyphs.image;

  /// 分享面板的另两个去向:文件、文字。
  static const shareFile = XrkGlyphs.fileText;
  static const shareText = XrkGlyphs.textAlignLeft;

  /// 刚生成的链接上的「停止分享」。
  static const stopSharing = XrkGlyphs.linkBreak;

  /// 分享出去的内容已隐藏密钥和个人路径。
  static const redacted = XrkGlyphs.shieldCheck;

  static const selectText = XrkGlyphs.textT;
  static const fork = XrkGlyphs.gitFork;
  static const regenerate = XrkGlyphs.arrowClockwise;
  static const edit = XrkGlyphs.pencilSimple;
  static const reply = XrkGlyphs.arrowBendUpLeft;

  /// 代码、diff 的自动换行开关。
  static const wrapLines = XrkGlyphs.textWrap;
  static const save = XrkGlyphs.downloadSimple;
  static const preview = XrkGlyphs.eye;

  /// 操作完成的回执:已复制、已保存。
  static const done = XrkGlyphs.check;

  // ── 通用操作 ────────────────────────────────────────────────
  static const add = XrkGlyphs.plus;

  /// 输入框尾部的「添加这一项」。
  static const addEntry = XrkGlyphs.plusCircleFill;
  static const increment = XrkGlyphs.plus;
  static const decrement = XrkGlyphs.minus;
  static const remove = XrkGlyphs.minusCircle;
  static const rename = XrkGlyphs.pencilSimpleLine;
  static const delete = XrkGlyphs.trash;

  /// 文件已被删掉的占位。
  static const deleted = XrkGlyphs.trash;

  /// 清空输入框。
  static const clear = XrkGlyphs.xCircleFill;
  static const clearAll = XrkGlyphs.broom;
  static const paste = XrkGlyphs.clipboard;
  static const download = XrkGlyphs.downloadSimple;
  static const refresh = XrkGlyphs.arrowClockwise;
  static const retry = XrkGlyphs.arrowClockwise;
  static const restart = XrkGlyphs.arrowCounterClockwise;
  static const search = XrkGlyphs.magnifyingGlass;
  static const configure = XrkGlyphs.slidersHorizontal;
  static const settings = XrkGlyphs.gearSix;
  static const link = XrkGlyphs.link;
  static const showSecret = XrkGlyphs.eye;
  static const hideSecret = XrkGlyphs.eyeSlash;
  static const newChat = XrkGlyphs.notePencil;
  static const newFolder = XrkGlyphs.folderPlus;
  static const newPost = XrkGlyphs.notePencil;
  static const moveToFolder = XrkGlyphs.folderArrowRight;
  static const multiSelect = XrkGlyphs.checkCircle;
  static const archive = XrkGlyphs.archive;
  static const unarchive = XrkGlyphs.boxArrowUp;
  static const exportLog = XrkGlyphs.archive;
  static const pin = XrkGlyphs.pushPin;
  static const pinActive = XrkGlyphs.pushPinFill;
  static const logout = XrkGlyphs.signOut;
  static const power = XrkGlyphs.power;

  /// 行、胶囊里的启动 / 暂停 / 停止:和别的操作一样用描边。
  static const play = XrkGlyphs.play;
  static const pause = XrkGlyphs.pause;
  static const stop = XrkGlyphs.stop;

  /// 回放的播放键:媒体控件按惯例用实心。
  static const mediaPlay = XrkGlyphs.playFill;
  static const mediaPause = XrkGlyphs.pauseFill;

  /// 回放播完后从头再放。
  static const replay = XrkGlyphs.arrowCounterClockwise;

  /// 回放页的「全文」。
  static const fullText = XrkGlyphs.article;
  static const enterPath = XrkGlyphs.cursorText;
  static const viewConfig = XrkGlyphs.fileText;

  /// 拿一条要在终端里跑的命令。
  static const command = XrkGlyphs.terminalWindow;
  static const fetchModels = XrkGlyphs.cloudArrowDown;
  static const testConnection = XrkGlyphs.broadcast;
  static const markAllRead = XrkGlyphs.checks;
  static const manageFolders = XrkGlyphs.arrowsDownUp;

  /// /compact:压缩上下文。
  static const compact = XrkGlyphs.arrowsInLineVertical;

  /// 完成后把思考与工具调用收成一行。
  static const foldTurns = XrkGlyphs.arrowsInLineVertical;

  // ── 选择与开关(选中 / 开启态用 Fill)──────────────────────
  /// 列表里当前选中的那一项。
  static const selected = XrkGlyphs.check;
  static const allowed = XrkGlyphs.check;
  static const radioOn = XrkGlyphs.checkCircleFill;
  static const radioOff = XrkGlyphs.circle;
  static const checkboxOn = XrkGlyphs.checkSquareFill;
  static const checkboxOff = XrkGlyphs.square;
  static const isDefault = XrkGlyphs.checkCircleFill;
  static const setDefault = XrkGlyphs.checkCircle;
  static const favorite = XrkGlyphs.star;
  static const favoriteActive = XrkGlyphs.starFill;
  static const bookmark = XrkGlyphs.bookmarkSimple;
  static const bookmarkActive = XrkGlyphs.bookmarkSimpleFill;
  static const postLike = XrkGlyphs.heart;
  static const postLikeActive = XrkGlyphs.heartFill;
  static const notifications = XrkGlyphs.bell;
  static const notificationsOn = XrkGlyphs.bellFill;
  static const notificationsOff = XrkGlyphs.bellSlash;

  // ── 状态 ────────────────────────────────────────────────────
  static const success = XrkGlyphs.checkCircleFill;
  static const completed = XrkGlyphs.checkCircle;
  static const error = XrkGlyphs.warningCircle;
  static const warning = XrkGlyphs.warning;
  static const info = XrkGlyphs.info;
  static const question = XrkGlyphs.question;
  static const attention = XrkGlyphs.exclamationMark;
  static const caution = XrkGlyphs.warningOctagon;

  /// 工具调用等的失败叉(配危险色)。
  static const failed = XrkGlyphs.x;
  static const stopped = XrkGlyphs.stopCircle;
  static const paused = XrkGlyphs.pauseCircle;
  static const blocked = XrkGlyphs.prohibit;
  static const pending = XrkGlyphs.circle;
  static const inProgress = XrkGlyphs.radioButton;
  static const stepFailed = XrkGlyphs.xCircleFill;
  static const stepSkipped = XrkGlyphs.minusCircle;
  static const loading = XrkGlyphs.hourglass;
  static const waiting = XrkGlyphs.hourglassHigh;
  static const running = XrkGlyphs.lightning;
  static const cannotDisplay = XrkGlyphs.prohibit;
  static const empty = XrkGlyphs.tray;
  static const toConfirm = XrkGlyphs.checkCircle;
  static const allRead = XrkGlyphs.checks;
  static const outputLimit = XrkGlyphs.textAlignLeft;
  static const imageBroken = XrkGlyphs.imageBroken;
  static const noResults = XrkGlyphs.magnifyingGlassX;
  static const noMatches = XrkGlyphs.funnelX;
  static const noFolder = XrkGlyphs.folderSlash;

  /// 主机或版本不支持这项能力。
  static const unsupported = XrkGlyphs.puzzlePieceSlash;
  static const taskBlocked = XrkGlyphs.lockSimple;

  // ── 连接、主机与引擎 ────────────────────────────────────────
  static const offline = XrkGlyphs.cloudSlash;
  static const disconnected = XrkGlyphs.linkBreak;
  static const reconnecting = XrkGlyphs.arrowsClockwise;
  static const engine = XrkGlyphs.cpu;
  static const engineStarting = XrkGlyphs.lightning;
  static const autoSwitch = XrkGlyphs.arrowsClockwise;
  static const cloud = XrkGlyphs.cloud;
  static const computer = XrkGlyphs.laptop;
  static const thisPhone = XrkGlyphs.deviceMobile;
  static const sshHost = XrkGlyphs.terminalWindow;
  static const remoteHost = XrkGlyphs.devices;
  static const remoteHosts = XrkGlyphs.devices;
  static const webConsole = XrkGlyphs.globe;
  static const checkUpdate = XrkGlyphs.arrowCircleUp;
  static const autoUpdate = XrkGlyphs.clockClockwise;

  // ── 安全与权限 ──────────────────────────────────────────────
  static const lock = XrkGlyphs.lockSimple;
  static const lockActive = XrkGlyphs.lockSimpleFill;
  static const unlock = XrkGlyphs.lockSimpleOpen;

  /// 凭据只留在本机。
  static const localOnly = XrkGlyphs.lockKey;
  static const approval = XrkGlyphs.shieldWarning;
  static const securityWarning = XrkGlyphs.shieldWarning;
  static const permissions = XrkGlyphs.shield;
  static const safeMode = XrkGlyphs.shieldPlus;
  static const verified = XrkGlyphs.shieldCheck;
  static const fingerprint = XrkGlyphs.fingerprint;
  static const apiKey = XrkGlyphs.key;
  static const noApiKey = XrkGlyphs.keySlash;
  static const autoApprove = XrkGlyphs.checks;

  // ── 文件与内容 ──────────────────────────────────────────────
  static const folder = XrkGlyphs.folder;

  /// 带分组色的实心文件夹(抽屉文件夹、文件列表)。
  static const folderMark = XrkGlyphs.folderFill;
  static const folderOpen = XrkGlyphs.folderOpen;
  static const workspace = XrkGlyphs.folder;
  static const workspaceGroup = XrkGlyphs.folders;
  static const defaultFolder = XrkGlyphs.folderStar;
  static const sharedStorage = XrkGlyphs.folderUser;
  static const home = XrkGlyphs.house;
  static const phoneStorage = XrkGlyphs.deviceMobile;
  static const downloads = XrkGlyphs.downloadSimple;
  static const document = XrkGlyphs.fileText;
  static const instructions = XrkGlyphs.fileText;
  static const file = XrkGlyphs.file;
  static const fileNew = XrkGlyphs.filePlus;
  static const diff = XrkGlyphs.gitDiff;
  static const pdf = XrkGlyphs.filePdf;
  static const image = XrkGlyphs.image;
  static const videoFile = XrkGlyphs.fileVideo;
  static const video = XrkGlyphs.filmStrip;
  static const audioFile = XrkGlyphs.fileAudio;
  static const audio = XrkGlyphs.musicNote;
  static const zip = XrkGlyphs.fileZip;
  static const slides = XrkGlyphs.slideshow;
  static const spreadsheet = XrkGlyphs.table;
  static const article = XrkGlyphs.article;
  static const plainText = XrkGlyphs.textAlignLeft;
  static const summary = XrkGlyphs.textAlignLeft;
  static const code = XrkGlyphs.code;
  static const diagram = XrkGlyphs.graph;
  static const artifacts = XrkGlyphs.package;
  static const shareBundle = XrkGlyphs.package;

  /// 文件还在生成。
  static const generating = XrkGlyphs.sparkle;

  // ── 图像与视频生成(docs/design/media-generation.md)──────────────
  /// ＋ 面板的「生成」磁贴、设置 › 图像与视频。
  static const generateMedia = XrkGlyphs.magicWand;

  /// 模式胶囊、参数弹层:图像 / 视频。
  static const generateImage = XrkGlyphs.image;
  static const generateVideo = XrkGlyphs.filmStrip;

  /// 查看器:「详情」。
  static const mediaDetails = XrkGlyphs.info;

  /// 查看器:变体、编辑、放大。
  static const mediaVary = XrkGlyphs.stack;
  static const mediaEdit = XrkGlyphs.pencilSimple;
  static const mediaUpscale = XrkGlyphs.arrowsInLineVertical;

  /// 权限胶囊:比工作区内修改更宽松。
  static const permissionRisky = XrkGlyphs.warning;
  static const web = XrkGlyphs.globe;
  static const readText = XrkGlyphs.note;

  // ── 功能 ────────────────────────────────────────────────────
  static const terminal = XrkGlyphs.terminalWindow;
  static const plugin = XrkGlyphs.puzzlePiece;
  static const pluginInventory = XrkGlyphs.listBullets;
  static const skill = XrkGlyphs.bookOpen;
  static const model = XrkGlyphs.cpu;
  static const providers = XrkGlyphs.sparkle;

  /// 模型列表里的一个模型。
  static const modelItem = XrkGlyphs.cpu;
  static const subagents = XrkGlyphs.treeStructure;
  static const workflow = XrkGlyphs.flowArrow;
  static const todo = XrkGlyphs.listChecks;
  static const goal = XrkGlyphs.flag;
  static const plan = XrkGlyphs.mapTrifold;
  static const planMode = XrkGlyphs.mapTrifold;
  static const jobs = XrkGlyphs.clipboardText;
  static const automation = XrkGlyphs.alarm;
  static const recurring = XrkGlyphs.repeat;
  static const scheduled = XrkGlyphs.clock;
  static const time = XrkGlyphs.clock;
  static const timeZone = XrkGlyphs.globe;
  static const commandTimeout = XrkGlyphs.timer;
  static const agentLoop = XrkGlyphs.arrowsClockwise;
  static const webSearch = XrkGlyphs.globeHemisphereWest;
  static const webApp = XrkGlyphs.globe;
  static const mention = XrkGlyphs.at;
  static const translate = XrkGlyphs.translate;
  static const history = XrkGlyphs.clockCounterClockwise;
  static const sessionDetails = XrkGlyphs.chartLineUp;
  static const trajectory = XrkGlyphs.path;
  static const diagnostics = XrkGlyphs.stethoscope;
  static const cordis = XrkGlyphs.squaresFour;

  /// Bot 发来的可交互面板。
  static const panel = XrkGlyphs.squaresFour;
  static const feedback = XrkGlyphs.chatCenteredDots;
  static const tool = XrkGlyphs.wrench;
  static const tip = XrkGlyphs.lightbulb;

  /// 伙伴小屋: she now and then asks you to rest with her (companion_page.dart).
  static const companionInvite = XrkGlyphs.chatTeardropText;

  /// 伙伴小屋: her words read aloud (companion_voice.dart). Not the microphone: that is the person's voice.
  static const companionVoice = XrkGlyphs.musicNote;

  /// 「问 AI」: a question about the app for the agent (ui/common/ask_ai.dart).
  static const askAi = XrkGlyphs.sparkle;

  /// 「给 xrk-mobile 点个 star」: the project on GitHub (ui/star/).
  static const starProject = XrkGlyphs.star;
  static const important = XrkGlyphs.sealWarning;
  static const theme = XrkGlyphs.palette;
  static const textSize = XrkGlyphs.textAa;
  static const phoneLayout = XrkGlyphs.deviceMobile;
  static const account = XrkGlyphs.userCircle;
  static const profile = XrkGlyphs.user;
  static const avatar = XrkGlyphs.userFill;
  static const balance = XrkGlyphs.wallet;
  static const shareConfig = XrkGlyphs.export;
  static const chart = XrkGlyphs.chartBar;

  /// 设置 › 宠物.
  static const pet = XrkGlyphs.smiley;

  /// 设置 › 隐私与分享.
  static const privacy = XrkGlyphs.lockKey;

  // ── 手机操控 ────────────────────────────────────────────────
  static const phoneControl = XrkGlyphs.handTap;
  static const readScreen = XrkGlyphs.scan;
  static const askFirst = XrkGlyphs.handPalm;
  static const askPerTask = XrkGlyphs.circleHalf;
  static const noConfirm = XrkGlyphs.lightning;
  static const appRules = XrkGlyphs.listChecks;
  static const dndMode = XrkGlyphs.stack;
  static const keepAlive = XrkGlyphs.batteryPlus;
  static const operate = XrkGlyphs.handPointing;
  static const alarmClock = XrkGlyphs.alarm;
  static const returnToApp = XrkGlyphs.arrowBendUpLeft;
  static const backgroundPrompt = XrkGlyphs.bell;
  static const overlayOpacity = XrkGlyphs.slidersHorizontal;
  static const overlayBall = XrkGlyphs.radioButton;

  /// 解除限制, its 「已解除限制」 tag, and its three rules.
  static const unlocks = XrkGlyphs.lockSimpleOpen;
  static const unlockSystem = XrkGlyphs.gearSix;
  static const unlockSecrets = XrkGlyphs.key;
  static const unlockOwnApp = XrkGlyphs.browser;

  /// 解除限制's confirmation page: what can go wrong, and the disclaimer.
  static const riskWarning = XrkGlyphs.shieldWarning;

  // ── 系统权限(首次启动的「按功能开启」与 设置 › 系统权限)──────
  static const systemAccess = XrkGlyphs.shieldCheck;
  static const fileAccess = XrkGlyphs.folderUser;
  static const accessibility = XrkGlyphs.scan;
  static const overlayPermission = XrkGlyphs.stack;
  static const highPower = XrkGlyphs.lightning;
  static const autostart = XrkGlyphs.power;
  static const backgroundPopUp = XrkGlyphs.boxArrowUp;

  // ── DS Bot 与群聊 ───────────────────────────────────────────
  static const bot = XrkGlyphs.robot;
  static const groupChat = XrkGlyphs.chats;
  static const newGroupChat = XrkGlyphs.userPlus;
  static const addMember = XrkGlyphs.userPlus;
  static const removeMember = XrkGlyphs.userMinus;
  static const makeAdmin = XrkGlyphs.crownSimple;
  static const team = XrkGlyphs.usersThree;
  static const conversations = XrkGlyphs.chats;
  static const chat = XrkGlyphs.chatCircle;
  static const announcement = XrkGlyphs.megaphone;
  static const nameTag = XrkGlyphs.identificationBadge;
  static const botRole = XrkGlyphs.briefcase;
  static const color = XrkGlyphs.palette;
  static const today = XrkGlyphs.calendarDot;
  static const lastWeek = XrkGlyphs.calendarDots;
  static const lastMonth = XrkGlyphs.calendar;
  static const fullLog = XrkGlyphs.receipt;
  static const working = XrkGlyphs.hammer;
  static const presetStandard = XrkGlyphs.wrench;
  static const presetMinimal = XrkGlyphs.square;
  static const presetCordis = XrkGlyphs.magicWand;
  static const presetPtc = XrkGlyphs.cards;

  // ── 论坛与社区 ──────────────────────────────────────────────
  static const forum = XrkGlyphs.chats;
  static const community = XrkGlyphs.usersFour;
  static const newTopic = XrkGlyphs.chatTeardropText;
  static const moved = XrkGlyphs.folderArrowRight;
  static const invite = XrkGlyphs.userPlus;
  static const reminder = XrkGlyphs.alarm;
  static const reaction = XrkGlyphs.smiley;
  static const badgeEarned = XrkGlyphs.medal;
  static const poll = XrkGlyphs.chartBar;
  static const playVideo = XrkGlyphs.playCircle;
  static const mail = XrkGlyphs.envelopeSimple;
  static const write = XrkGlyphs.notePencil;
  static const featured = XrkGlyphs.sparkle;
  static const bug = XrkGlyphs.bug;
  static const school = XrkGlyphs.graduationCap;
  static const travel = XrkGlyphs.suitcase;
  static const calendar = XrkGlyphs.calendarBlank;

  /// 社区里的外部渠道。
  static const wechat = XrkGlyphs.chatCircleFill;
  static const qq = XrkGlyphs.usersThreeFill;
  static const telegram = XrkGlyphs.paperPlaneRight;
  static const discord = XrkGlyphs.headset;
}
