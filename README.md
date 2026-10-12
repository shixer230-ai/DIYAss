# DIYAss —— DIY 硬件性价比助手

一个帮你从 CPU / 显卡到整机方案，挑出最划算配置的安卓 App。

面向不懂硬件的小白用户：提供硬件库浏览、性价比排行、兼容性检测、整机方案管理、AI 分析，帮你拼出预算内最值、互相兼容的装机方案。

## 主要功能

- **硬件库**：预置 300+ 主流型号（CPU / 显卡 / 主板 / 内存 / 硬盘 / 电源 / 机箱），含参数与参考跑分，支持关键词搜索、品牌分组、「我的添加」自定义型号
- **整机方案**：多方案管理、按槽位选配、方案内直接填价实时算总价、一键保存到清单、兼容性检测（CPU↔主板插槽、内存代别、电源功率）
- **性价比分析**：CPU-Z 单核/多核、3DMark、整机功耗、自定义项目四种排行，胶囊柱状条
- **AI 分析 / 可靠性分析**：云端调用 DeepSeek，分析整机瓶颈与硬件稳定性风险（魔改 CPU / 矿卡 / 洋垃圾等）
- **云方案**：登录用户可把整机方案上传到「硬件库 → 云方案」公开分享，支持点赞、按获赞排序、本地关键字搜索、删除自己的方案
- **云同步**：账号（邮箱验证码注册 / 密码登录 / 验证码登录）、整机方案上传 / 从云恢复 / 删除、自定义项目云同步、头像云存储
- **捐赠 donator**：爱发电订单号自助开通，专属标识 + 每日 AI 50 次 + 云方案每日上传 5 次
- **配置单导入导出**：一键导出为文本（系统分享面板），一键粘贴还原整机方案
- **版本更新检测**：打开「我的」页自动检测 GitHub 最新 release，有新版本红字提示
- **液态玻璃 UI**：iOS 风格底部导航（真实折射 + 跟手滑动）、胶囊圆角 + 半透明卡片

## 技术栈

- **Flutter / Dart** 客户端
- **腾讯云 CloudBase**：云数据库 + 云函数 + 云存储 + 认证
- **云函数 Node.js**（`@cloudbase/node-sdk`）
- **DeepSeek API**：AI 分析（Key 只存云函数环境变量，不打进安装包）

## 目录结构

```
DIYHelper/
├── app/                    # Flutter 客户端
│   └── lib/
│       ├── pages/          # 页面
│       ├── cloud/          # 云同步 / 认证 / 版本检测
│       ├── models/         # 数据模型
│       ├── storage/        # 本地存储
│       ├── ai/             # AI 分析
│       ├── analysis/       # 性价比 / 兼容性算法
│       └── utils/          # 工具
├── cloudfunctions/         # 云函数（各函数独立部署）
│   ├── publishPlan/        # 方案上传（每日限额 + 关键词合规）
│   ├── likePlan/           # 云方案点赞
│   ├── deleteCloudPlan/    # 删除自己的云方案
│   ├── cleanupPlans/       # 定时清理 0 赞老方案（每天 3 点）
│   ├── aiChat/             # AI 分析（DeepSeek 代理 + 每日限流）
│   ├── publishHardware/    # 发行硬件库
│   └── verifyDonation/     # 爱发电订单号开通 donator
└── PROJECT_PLAN.md         # 项目规划文档
```

## 构建

```bash
cd app
flutter pub get
flutter build apk --release
```

产物：`app/build/app/outputs/flutter-apk/app-release.apk`

## 版权

CreativeDesign ZkeRurQwQ · 蓝色大肥鱼Accomplish

> 版权署名，请勿盗用。
