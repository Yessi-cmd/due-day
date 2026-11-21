# AGENTS.md

本文件是给 AI 编码代理（以及未来的我）看的项目说明书。动手改代码前先通读一遍；与本文冲突的实现视为 bug。

---

## 1. 项目概述

一个**只给我自己 iPhone 使用**的提醒 App，核心场景：

- **订阅服务续费**（视频会员、云盘、App 订阅、域名、VPS……）
- **分期服务还款**（信用卡分期、花呗/白条分期、手机分期……）
- **房租缴费**（月付 / 季付 / 半年付 / 年付）
- 以及任何用户**自定义**的周期性或一次性提醒

附带一个**完整、正确的日历**：公历 + 中国农历（含闰月）+ 二十四节气 + 传统节日 / 公历节日。

开发环境是 **Windows**，本地没有 Mac 和 Xcode。**所有编译、测试、签名、打包都在 GitHub Actions 的 macOS runner 上完成**，产物是一个可直接装到我手机上的 `.ipa`。

---

## 2. 签名与证书（硬约束，不可更改）

项目根目录下的 `证书_00008140-0006306201E0801C/` 中有：

| 文件 | 说明 |
|---|---|
| `证书文件.p12` | 分发证书 + 私钥 |
| `密码.txt` | p12 的密码 |
| `描述文件.mobileprovision` | Ad-hoc 描述文件 |

从描述文件中读出的关键信息：

| 项 | 值 |
|---|---|
| 类型 | Ad-hoc（`get-task-allow = false`，仅 1 台设备） |
| 设备 UDID | `00008140-0006306201E0801C` |
| Team ID | `M8CDNJ6X6H` |
| **Bundle ID** | **`app.aurora7963.honey1287`**（显式 App ID，必须一字不差） |
| 签名身份 | `iPhone Distribution: Duane Hudgens (M8CDNJ6X6H)` |
| 描述文件 UUID | `530dd972-4514-44db-8ddf-59dccbdc4a8d` |
| 描述文件名 | `00008140-0006306201E0801CH5PHUT` |
| 到期 | 2027-11-18（证书与描述文件同时到期） |
| 可用能力（与本项目相关） | `aps-environment`、`usernotifications.time-sensitive`、App Groups（`group.07ebc045030d1934.1`~`.5`） |

由此推出的约束：

1. **只能有一个 target 被签名**：描述文件是针对单一显式 App ID 的，**不能做 Widget、通知扩展等任何 App Extension**（它们需要独立的 Bundle ID 和描述文件）。所有功能必须在主 App 内实现。
2. **不用 iCloud / CloudKit**：描述文件里 iCloud 容器列表为空，无法使用。数据只存本地，并提供导出/导入备份。
3. **不用远程推送**：所有提醒都用**本地通知**（`UNUserNotificationCenter`），不依赖服务器。
4. 证书是第三方团队名下的，**存在被吊销的可能**。因此"数据备份导出"是必须功能，不是可选功能。
5. 证书到期或换证书时，只需要替换 GitHub Secrets，不应需要改代码。Bundle ID、Team ID、描述文件名等全部集中在 `project.yml` / CI 环境变量中，不得散落在代码里。

### 2.1 证书安全（必须遵守）

- **证书目录、`.p12`、`.mobileprovision`、`密码.txt` 永远不得提交进 git。** 仓库初始化时第一件事就是写 `.gitignore`：
  ```gitignore
  证书_*/
  *.p12
  *.mobileprovision
  *.cer
  密码.txt
  ```
- 它们以 GitHub Actions Secrets 的形式提供给 CI（见第 8 节）。
- 代理不得在日志、提交信息、PR 描述、代码注释中输出 p12 密码或 base64 内容。

---

## 3. 技术栈

| 项 | 选择 | 理由 |
|---|---|---|
| 语言 | Swift 6（开启严格并发检查，警告即修） | |
| UI | **SwiftUI** | |
| 最低系统 | **iOS 17.0** | 可用 SwiftData、`@Observable`、新版 `ContentUnavailableView` 等 |
| 持久化 | **SwiftData** | 本地存储 |
| 通知 | `UserNotifications` 本地通知 | |
| 后台刷新 | `BackgroundTasks`（`BGAppRefreshTask`） | 补发通知队列 |
| 工程生成 | **XcodeGen**（`project.yml`） | Windows 下无法用 Xcode 编辑 `.pbxproj`；**不要提交 `.xcodeproj`**，CI 中现场生成 |
| 测试 | Swift Testing（`import Testing`）为主，XCTest 可用于 UI 测试 | |
| 第三方依赖 | **原则上零依赖** | 日期/农历全部基于 Foundation；确有必要时用 SPM，需在本文件登记理由 |

只支持 iPhone、竖屏。界面语言以**简体中文**为主（`zh-Hans`），字符串仍走 String Catalog（`Localizable.xcstrings`），不要硬编码在视图里。

---

## 4. 目录结构

```
ios-app1/
├── AGENTS.md
├── .gitignore
├── project.yml                     # XcodeGen 配置（唯一的工程定义来源）
├── ExportOptions.plist             # 导出 ipa 用
├── .github/workflows/
│   ├── ci.yml                      # PR / push：编译 + 单元测试
│   └── release.yml                 # 手动触发 / 打 tag：签名打包 ipa + 发布 OTA 安装页
├── distribution/                   # OTA 安装页与 manifest 模板（见 8.4）
├── scripts/                        # set-signing-secrets.sh、gen-icon.mjs 等工具脚本
├── Reminder/                       # App 源码
│   ├── App/                        # 入口、AppDelegate、依赖装配
│   ├── Models/                     # SwiftData 模型
│   ├── Calendar/                   # ★ 日历内核：农历、节气、节日、重复规则（纯逻辑，无 UI）
│   ├── Scheduling/                 # 通知调度
│   ├── Features/
│   │   ├── Upcoming/               # 首页：即将到期
│   │   ├── CalendarView/           # 日历页
│   │   ├── ReminderEditor/         # 新建/编辑提醒
│   │   └── Settings/               # 设置、备份
│   ├── DesignSystem/               # 颜色、字体、通用组件
│   └── Resources/                  # Assets、xcstrings、节气/节假日数据
└── ReminderTests/                  # 单元测试（日历内核是重点）
```

`Calendar/` 与 `Scheduling/` 中的代码必须是**纯逻辑、可单测、不依赖 SwiftUI / SwiftData**，通过注入 `Calendar`、`TimeZone`、`now` 来保证可测试性。**禁止在业务逻辑中直接调用 `Date()` 或 `Calendar.current`**，统一通过一个可注入的 `Clock` / 环境对象获取。

---

## 5. 日历内核（最高优先级的正确性要求）

> 日历出错 = 提醒出错 = 这个 App 没有存在意义。这一节的每一条都需要对应的单元测试。

### 5.1 总原则

1. **永远不要手写日期算术。** 不准用 `86400` 秒代表一天、不准自己写"是否闰年"、不准自己写"每月几天"。一律用 `Calendar` 的 `date(byAdding:)`、`range(of:in:for:)`、`dateComponents`、`nextDate(after:matching:)` 等 API。
2. **公历**使用 `Calendar(identifier: .gregorian)`；**农历**使用 `Calendar(identifier: .chinese)`。两者都显式设置 `locale = zh_CN`。
3. **农历计算必须把 `timeZone` 固定为 `Asia/Shanghai`（UTC+8）。** 农历的朔日、节气是按北京时间定义的；如果用设备当前时区（比如出差在美国），初一可能错一天。公历显示和通知触发则使用设备当前时区。
4. **支持范围：1901-01-01 ～ 2099-12-31**。超出范围时日历页不允许翻过去，日期选择器也限制在此范围。
5. **重复事件的每一次发生都从"锚点"推算，而不是从"上一次发生"推算。** 否则 1 月 31 日 → 2 月 28 日 → 3 月 28 日，会永久漂移。正确做法：第 n 次 = 锚点 + n × 周期，再按规则夹到当月有效日期。

### 5.2 公历

- 闰年由 `Calendar` 处理：2000 年是闰年，1900、2100 年不是，2024、2028 是。
- 每周起始日可设置，**默认周一**（中国习惯），其次周日。
- 日历页显示 ISO 周数可选（默认关）。

### 5.3 农历

由 `Calendar(identifier: .chinese)` 提供，需要额外封装出：

- 农历年月日：`DateComponents.year / month / day / isLeapMonth`
  - 注意：`.chinese` 日历的 `year` 是 **60 甲子循环中的序号（1–60）**，`era` 是第几个甲子。不要把它当成公元年。
- **干支纪年**（如"乙巳年"）、**生肖**（如"蛇"）—— 由甲子序号换算
- 农历月名：正月、二月……冬月、腊月；闰月前加"闰"（如"闰六月"）
- 农历日名：初一……初十、十一……二十、廿一……廿九、三十
- **大月 30 天 / 小月 29 天**：通过 `range(of: .day, in: .month, for:)` 获取，不得假设
- 公历 ↔ 农历双向转换。农历 → 公历时，要能指定是否闰月；若指定的闰月当年不存在，返回 `nil`，由上层按 5.6 规则处理

### 5.4 二十四节气

Foundation **不提供**节气。实现方式：

- 在 `Resources/` 中内置 **1901–2099 年节气时刻表**（精确到分钟，北京时间），JSON 格式，作为数据而非代码。
- 数据要从权威来源（紫金山天文台 / 香港天文台公布的数据，或基于 VSOP87 / 寿星天文历算法离线生成）得到，**生成脚本放在 `scripts/` 下一并提交**，注明来源。
- 节气归属日期 = 节气时刻在**北京时间**所在的那一天。
- 测试需覆盖抽样年份的若干节气与权威数据比对。

### 5.5 节日

| 类别 | 例子 | 规则 |
|---|---|---|
| 公历固定节日 | 元旦、劳动节、国庆、圣诞 | 固定月日 |
| 农历固定节日 | 春节、元宵、端午、七夕、中秋、重阳、腊八 | 农历月日，**只匹配非闰月**（闰五月初五不是端午） |
| **除夕** | — | **农历年最后一天**：腊月可能只有 29 天，此时除夕是腊月廿九，**不能写死为腊月三十** |
| 节气型节日 | 清明 | 取自节气表 |
| 按周推算 | 母亲节（5 月第 2 个周日）、父亲节（6 月第 3 个周日） | 用 `weekdayOrdinal` |
| 法定节假日 / 调休 | 放假、补班 | **每年由国务院公布，无法推算**。内置 `holidays_cn.json`，按年存放；App 内显示"休"/"班"角标。缺少某年数据时不显示，不要猜测 |

日历格子里副标题的优先级：**节日 > 节气 > 农历日**（初一显示月名，如"闰六月"）。

### 5.6 边界情况与既定处理规则

| 场景 | 规则 |
|---|---|
| 每月 29/30/31 号的提醒，遇到没有这一天的月份 | 落到**当月最后一天**；下个月恢复原日期（锚点推算，不漂移） |
| 每年 2 月 29 日的提醒，遇到平年 | 落到 **2 月 28 日** |
| "每月最后一天" | 独立的规则选项，不等同于"每月 31 号" |
| 农历每年某月三十，遇到当年该月是小月 | 落到**该月廿九** |
| 农历闰月日期（如闰四月初八）作为每年重复 | 当年**有**该闰月 → 用闰月；**没有** → 用同名的普通月 |
| 农历每月初一 / 十五 | 支持；闰月也算一个月，照常提醒 |
| 设备时区变化 / 用户出行 | 提醒按"本地墙上时间"（floating time）存储：保存 `年月日 + 时分`，不保存绝对时间戳；监听 `NSSystemTimeZoneDidChange` 后**全部重新调度** |
| 夏令时（本地无 DST，但需兼容） | 通知 trigger 用 `DateComponents`，不用秒数偏移；不存在的时刻顺延到下一个有效时刻 |
| 系统日期被修改 / 跨天 | 监听 `NSCalendarDayChanged` 与 `significantTimeChange`，刷新 UI 并重排通知 |
| 可选：遇周末/法定节假日调整 | 提醒项可选"提前到前一个工作日"（适合房租），依赖 `holidays_cn.json`；默认关闭 |

### 5.7 必须存在的测试用例（最低集合）

实现时要用权威万年历**复核**每个预期值后再写进测试；以下为必测清单：

- 公历闰年：1900 / 2000 / 2024 / 2100 的 2 月天数
- 月末钳制：锚点 1-31 每月重复，连续 14 个月的结果（含闰年 2 月、平年 2 月、4/6/9/11 月），且 3 月回到 31 号
- 2-29 每年重复：2024 → 2025 → 2028 的结果
- 农历闰月识别：2020 闰四月、2023 闰二月、2025 闰六月、**2033 闰十一月**（著名的"2033 年问题"）
- 春节公历日期：抽样 2020、2023、2024、2025、2026、2027
- 除夕在腊月廿九的年份（如 2025 年 1 月 28 日）
- 农历每年"三十"在小月年份的钳制
- 闰月生日在无闰月年份落到普通月
- 设备时区设为 `America/Los_Angeles` 时，农历初一判定不变
- 支持范围两端 1901-01-01、2099-12-31 可正常转换，越界返回 `nil` 不崩溃
- 节气抽样比对、母亲节/父亲节推算

---

## 6. 提醒项（领域模型）

### 6.1 提醒类型

| 类型 | 特有字段 | 特有行为 |
|---|---|---|
| **订阅** `subscription` | 服务名、金额、币种、周期、付款方式、是否自动续费、试用期结束日（可选） | 试用期结束前单独提醒；可标记"已取消"后不再提醒；统计月均/年均支出 |
| **分期** `installment` | 总期数、首期还款日、每期金额、已还期数、平台 | 显示"第 n / N 期"、剩余金额；**最后一期后自动结束**；全部还完显示"已结清" |
| **房租** `rent` | 金额、周期（月/季/半年/年）、交租日、房东/收款方、合同到期日（可选） | 合同到期前额外提醒；可选"遇节假日提前" |
| **自定义** `custom` | 标题、备注 | 通用 |

所有类型共享：标题、图标（SF Symbol）、颜色、金额（可选，用 `Decimal`，**禁止用 `Double` 存钱**）、币种（默认 CNY）、备注、是否归档、创建/修改时间。

### 6.2 重复规则 `RecurrenceRule`

- 历法：**公历 / 农历**
- 频率：不重复 / 每 N 天 / 每 N 周（可选周几）/ 每 N 月（按几号 或 最后一天）/ 每 N 年
- 结束条件：永不 / 截止日期 / 共 N 次（分期类型自动用期数）
- 规则是纯值类型（`Codable` struct），由 `Calendar/` 模块中的 `OccurrenceGenerator` 生成任意区间内的发生日期——UI、通知、统计全都调用它，**不允许别处另写一套日期推算**。

### 6.3 提醒时机

- 每个提醒项可设置**多个提前量**：当天、提前 1/2/3/5/7/15/30 天，或自定义 N 天；默认"提前 3 天 + 当天"
- 提醒时刻（时:分），默认 09:00，全局可改默认值
- 当天提醒默认用 **Time Sensitive** 中断级别（描述文件已授权 `time-sensitive`），提前提醒用普通级别；可在设置中关闭

### 6.4 支付记录

- 每次发生（occurrence）可**标记"已付"**，记录实付金额与日期（可编辑）。
- 某次已标记已付 → 取消该次剩余的通知。
- 过期未标记 → 首页显示"已逾期"，通知中心不再重复轰炸（只在逾期当天和次日各提醒一次）。
- 通知支持**操作按钮**："已付"、"明天再提醒"——无需打开 App 即可处理。

---

## 7. 通知调度

iOS 每个 App **最多同时挂 64 个待发本地通知**，而且 `UNCalendarNotificationTrigger(repeats: true)` 无法表达月末钳制、农历、分期结束等规则。因此：

1. **不使用重复型 trigger。** 每条通知都是一次性的、带完整 `年月日时分` 的 `DateComponents` trigger。
2. `NotificationScheduler` 的工作方式：用 `OccurrenceGenerator` 生成未来一段时间（如 90 天）内所有提醒项的所有通知时刻 → 排序 → 取最早的 **60 条**（留 4 条余量）→ 与当前挂起的通知做 diff → 增删。
3. 通知 identifier 规则：`<reminderID>.<occurrenceDate yyyyMMdd>.<offsetDays>`，保证幂等。
4. 触发重排的时机：App 启动、回到前台、任何提醒项增删改、标记已付、时区/日期显著变化、`BGAppRefreshTask` 执行时（每天至少申请一次）。
5. 通知权限被拒时，首页顶部显示一条可点击的提示条引导去设置，不弹窗打扰。
6. 设置页提供"查看已排队通知"的调试列表（显示条数和最近 10 条），方便排查。

---

## 8. GitHub Actions

### 8.1 Secrets

**不要手工配置**，统一用脚本（本机需已 `gh auth login`，Git Bash 或 macOS 均可）：

```bash
bash scripts/set-signing-secrets.sh "证书_00008140-0006306201E0801C" Yessi-cmd/due-day
```

脚本会：把 p12 重新编码为 3DES/SHA1（原文件是 OpenSSL 3 默认的 PBES2/AES-256，macOS `security import` 可能拒绝），并换上随机强密码（原密码只有一个字符，作为 Secret 会导致 Actions 日志里所有同样的字符都被打码）；打印证书与描述文件信息供核对；写入以下 4 个 Secrets：

| Secret | 内容 |
|---|---|
| `P12_BASE64` | 重新编码后的 p12（base64） |
| `P12_PASSWORD` | 重新编码后 p12 的随机密码 |
| `PROVISION_PROFILE_BASE64` | 描述文件（base64） |
| `KEYCHAIN_PASSWORD` | 随机字符串，用于 CI 临时钥匙串 |

换证书时：把新证书目录放进项目根目录（已被 .gitignore 忽略），重跑脚本；若描述文件名 / Bundle ID / Team ID 变了，脚本会警告，再按第 2 节修改 `project.yml` 与 `ExportOptions.plist`。

### 8.2 `ci.yml`（每次 push / PR）

- runner：`macos-15`（或当时最新的稳定 macOS 镜像），用 `xcode-select` 固定 Xcode 版本
- `brew install xcodegen` → `xcodegen generate`
- `xcodebuild test` 在 iOS Simulator 上跑全部单元测试
- 不需要任何证书

### 8.3 `release.yml`（手动 `workflow_dispatch` 或推送 `v*` tag）

步骤：

1. 生成工程（同上）
2. 创建临时钥匙串 → 导入 p12（`security import ... -T /usr/bin/codesign`）→ `security set-key-partition-list` → 设为默认搜索列表
3. 把描述文件解码到 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`（Xcode 16+）和 `~/Library/MobileDevice/Provisioning Profiles/`（旧版），文件名为 `<UUID>.mobileprovision`
4. `xcodebuild archive`，**手动签名**：
   - `CODE_SIGN_STYLE=Manual`
   - `DEVELOPMENT_TEAM=M8CDNJ6X6H`
   - `CODE_SIGN_IDENTITY="iPhone Distribution"`
   - `PROVISIONING_PROFILE_SPECIFIER=<描述文件名或 UUID>`
   - `PRODUCT_BUNDLE_IDENTIFIER=app.aurora7963.honey1287`
5. `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist`
   - `method`：`release-testing`（Xcode 15.3+ 中 Ad-hoc 的新名字；旧版 Xcode 用 `ad-hoc`）
   - `signingStyle: manual`，`provisioningProfiles` 映射 Bundle ID → 描述文件名
   - `teamID: M8CDNJ6X6H`
6. 上传 `.ipa` 为 workflow artifact；若是 tag 触发，同时创建 GitHub Release 并附上 ipa
7. 生成 OTA 安装页（见 8.4），用 `upload-pages-artifact` 上传；独立的 `deploy` job 用 `deploy-pages` 发布到 GitHub Pages
8. `if: always()` 步骤中删除临时钥匙串和描述文件

版本号：`MARKETING_VERSION` 取自 tag（如 `v1.2.0` → `1.2.0`），`CURRENT_PROJECT_VERSION` 取 `github.run_number`。

Entitlements 文件只声明本项目真正用到的能力（`aps-environment` 用不到就不要声明；Time Sensitive 需要 `com.apple.developer.usernotifications.time-sensitive = true`）。**声明的能力必须是描述文件能力的子集**，否则签名失败。

### 8.4 安装到手机（OTA）

产物是 Ad-hoc 签名的 ipa，只能装到 UDID 为 `00008140-0006306201E0801C` 的设备上。

**安装方式：iPhone 用 Safari 打开 https://yessi-cmd.github.io/due-day/ ，点「安装」。** 电脑打开该页会显示二维码，用手机相机扫码即可。

实现：
- 模板在 `distribution/`：`index.html`（安装页）与 `manifest.plist`（`itms-services` 清单），占位符 `__XXX__` 由 `release.yml` 用实际版本、构建号、URL 填充；填充后若仍有占位符则构建失败。
- 站点内容：`index.html`、`manifest-<构建号>.plist`（带构建号避免 iOS 缓存）、ipa、图标（`sips` 缩放出 57/512）、`qr.svg`（`qrencode` 生成）。
- 每次 Release 都会覆盖整个站点，只保留最新版本；历史版本见 Actions artifacts 或 GitHub Releases。
- Pages 已设为「GitHub Actions」部署；`github-pages` 环境允许 `main` 分支和 `v*` tag 部署。

如果证书被吊销，App 会闪退——这就是第 6、9 节强调备份的原因。

> 费用提示：public 仓库 macOS runner 免费；private 仓库的 macOS 分钟数按 10 倍计费。仓库设为 public 也没问题，前提是证书**只在 Secrets 里**。

---

## 9. 界面设计：清新、简约

### 9.1 风格

- **留白多、层级少、颜色少**。整体白（深色模式下近黑）底，**只有一个主色**（建议薄荷绿 / 青绿系，如 `#2BB5A0` 一类），其余全部用系统灰阶。
- 字体：系统字体（SF Pro / 苹方），用 Dynamic Type 文本样式（`.title2`、`.body`、`.footnote`……），不写死字号。数字金额用 `.monospacedDigit()`。
- 图标：只用 SF Symbols，线性风格。
- 卡片：大圆角（16pt，`continuous`）、无边框或极淡阴影；不用渐变、不用拟物、不用花哨动效。
- 动画：仅系统默认过渡 + 轻微 spring；尊重"减弱动态效果"。
- 必须完整支持：**深色模式**、**Dynamic Type**（到 AX 大字号布局不崩）、**VoiceOver** 标签。
- 颜色、间距、圆角集中在 `DesignSystem/` 定义为 token，视图中不直接写色值。

### 9.2 页面结构（底部 TabView，三个 Tab）

**① 即将到期（首页）**
- 顶部一张摘要卡：本月待付总额、本月已付、订阅月均支出
- 列表分组：已逾期（红色小标）/ 今天 / 7 天内 / 本月 / 以后
- 每行：图标 + 标题 + 剩余天数（"3 天后" / "今天" / "逾期 2 天"）+ 金额；分期显示"6/12 期"
- 左滑"已付"，右滑"编辑"；右上角"+"新建
- 空状态用 `ContentUnavailableView`，一句话 + 一个新建按钮

**② 日历**
- 月视图网格，6 行固定高度；每格：公历日（大）+ 副标题（节日 / 节气 / 农历日，小字灰色）+ 底部小圆点表示当天有提醒（颜色取提醒项颜色，最多 3 个）
- 今天：主色实心圆；选中：主色描边；周末日期稍浅；非本月日期更浅；法定节假日右上角"休"，调休上班"班"
- 左右滑动切换月份，标题点击弹出年月选择器，"今天"按钮回到当天
- 网格下方：选中日的详情——`2025年7月25日 星期五`、`乙巳年（蛇） 闰六月初一`、节气/节日，以及当天的提醒列表

**③ 设置**
- 默认提醒时刻、默认提前量、每周起始日、Time Sensitive 开关、是否显示节假日
- 通知权限状态
- **数据备份**：导出 JSON（通过 ShareLink / 文件 App），导入 JSON（导入前预览条数，支持合并或覆盖）
- 关于：版本号、构建号、证书到期日（构建时注入，到期前 30 天在首页提示）

**新建/编辑提醒**
- 第一步选类型（订阅 / 分期 / 房租 / 自定义，四个大卡片），之后是按类型定制的表单；只展示该类型需要的字段，高级选项折叠
- 日期选择器可切换"公历 / 农历"；农历模式用滚轮选择 年 / 月（含闰月选项，仅当年确有闰月时出现）/ 日（按该月实际天数）
- 表单底部实时预览"接下来 3 次提醒时间"，让用户确认规则正确

---

## 10. 数据与备份

- SwiftData 模型需带 `schemaVersion`，用 `VersionedSchema` + `SchemaMigrationPlan` 管理迁移；**任何模型改动都必须附带迁移**，不得导致老数据丢失。
- 导出格式：带版本号的 JSON（`{ "version": 1, "exportedAt": ..., "reminders": [...], "payments": [...] }`），日期用 ISO 8601，金额用字符串表示的十进制数。
- 导入需容错：未知字段忽略，缺失字段用默认值，版本过高时提示而不是崩溃。
- 导出/导入要有往返测试（导出 → 导入 → 数据完全一致）。

---

## 11. 代理工作规范

- **本地无法编译**（Windows）。每次改动后通过 push 触发 `ci.yml` 验证；不能假设代码"应该能编译"。提交前至少自查：import 是否齐全、Swift 6 并发标注（`@MainActor`、`Sendable`）、`project.yml` 是否包含新文件路径。
- 新增任何日期相关逻辑 → 必须同时新增单元测试。修复日期 bug → 先写复现测试再修。
- 不要引入：广告、统计、网络请求、账号系统、任何第三方 SDK。这个 App 完全离线。
- 不要生成或提交 `.xcodeproj`、`DerivedData`、`build/`、`*.ipa`。
- 改动 `project.yml`、entitlements、workflow 时，在提交信息中写明原因。
- 用户可见文案用简体中文，语气简洁友好；代码标识符、注释用英文。
- 涉及第 2 节签名信息的任何变化（换证书、换 Bundle ID），只改 `project.yml`、`ExportOptions.plist` 与 Secrets，不改 Swift 代码。

---

## 12. 里程碑

1. **M0 脚手架**：`.gitignore`、`project.yml`、空白 SwiftUI App、`ci.yml` 跑通、`release.yml` 产出可安装的 ipa 并在真机上打开 ✅ 先验证签名链路
2. **M1 日历内核**：公历/农历转换、节气数据、节日、`OccurrenceGenerator`，第 5.7 节全部测试通过
3. **M2 日历页**：月视图 + 日详情
4. **M3 提醒项**：模型、四种类型的编辑器、首页列表
5. **M4 通知**：调度器、通知操作按钮、后台刷新、标记已付
6. **M5 打磨**：统计摘要、备份导入导出、深色模式/大字号/VoiceOver 走查、证书到期提示
