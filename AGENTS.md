# Repository Guidelines

## 项目结构与模块划分

本目录是《饥荒联机版》的客户端模组 **Auto Attack**。`modinfo.lua` 定义模组信息与默认选项；`modmain.lua` 注册按键、保存本机设置并调度组件。`scripts/autoattack/controller.lua` 调度动作观察与交替走位；`scripts/autoattack/remote.lua` 负责关闭延迟补偿时的攻击重试、原生靠近和新攻击识别；`scripts/autoattack/cadence.lua` 负责普通近战的固定节拍、保持/释放攻击控制和异常重新对齐；`scripts/autoattack/timing.lua` 定义手动等待与固定超时；`scripts/autoattack/weapons.lua` 定义普通攻击的武器分类、动画与出手阶段；`scripts/widgets/autoattacksettings.lua` 实现暂停菜单中的手感面板，`scripts/widgets/autoattackslider.lua` 提供固定尺寸的可拖动滑条。界面使用游戏自带的 `TEMPLATES.CurlyWindow`、`StandardButton` 及原版贴图；修改外观时优先复用这些素材，避免重新绘制直角面板。`README.md` 记录操作、算法和限制，`tests/` 包含独立 Lua 模拟测试。

`cover.png` 是封面原图，`modicon.png` 是 256 像素图标源图，`modicon.tex` 和 `modicon.xml` 为游戏图标。二进制纹理应使用转换工具修改。

## 构建、测试与本地开发

项目没有构建或依赖安装步骤。在项目根目录执行：

```sh
luac -p modinfo.lua modmain.lua scripts/autoattack/timing.lua scripts/autoattack/cadence.lua scripts/autoattack/remote.lua scripts/autoattack/weapons.lua scripts/autoattack/controller.lua scripts/widgets/autoattacksettings.lua scripts/widgets/autoattackslider.lua
lua tests/test_timing.lua
lua tests/test_controller.lua
lua tests/test_remote.lua
lua tests/test_pausemenu.lua
lua tests/test_loading.lua
lua tests/test_settings.lua
```

语法检查和模拟测试无法替代游戏实测。将运行文件复制到 DST 安装包的 `dontstarve_steam.app/Contents/mods/auto_attack/` 后启用模组。开发修改以本目录为准。

## 编码风格与配置

Lua 使用四空格缩进，局部变量和函数使用 `snake_case`，DST API 保持原名。保留已有 Lua 文件的 CRLF 换行。没有配置格式化工具。代码中不添加注释，算法与维护说明写入 `README.md`。保持 `Attack_key` 兼容；持久化设置变更时校验数值范围和存储格式。

设计基准是关闭延迟补偿、平均 ping 不超过 140 ms。客户端不能把动画、状态标记或 ping 当作服务器命中确认。未知动作应跳过自动后撤。模组不读取 ping，也不自动增加等待；旧自动辅助设置必须忽略。修改普通武器时序时，对照当前安装游戏的状态图，并更新 README 和测试。

## 验证要求

测试按 `tests/test_*.lua` 命名并模拟 DST 对象。修改行为后覆盖非预测移动 RPC、按键响应、缓冲边界、取消动作、手动操作优先、超时，以及交替走位限距、冷却后继续攻击、首次选敌靠近、Ctrl 强制攻击、不同武器出手时机、女武神战矛及警告表已播放动画的剩余等待与变更动画回退、非预测客户端的原生冷却未计时场景、59 ms 连续多击及上下行延迟变化，以及换武器取消走位。`test_remote.lua` 必须保留服务器冷却、收发延迟、攻击标记滞后和原生选敌约束，检查一次出手仅移动一次，不能把重复请求当作实际攻击。测试不得连接真实服务器。网络延迟可以作为收发模拟参数，但必须检查运行时代码不调用 `GetAveragePing`。固定节拍测试须模拟按住攻击的服务器续攻、指令顺序和停止控制，核对稳定条件下的走位间隔、每击最多一步及松键释放。

实机验证关闭延迟补偿下的本机洞穴与远程服务器、普通近战武器、暂停菜单手感面板及设置保存。记录未完成的实机验证，不将模拟测试表述为已验证游戏手感。

## 提交与拉取请求

使用简短动词式提交信息，例如 `Fix non-predicting retreat input`。拉取请求说明行为变化、测试结果及限制；界面改动附实机截图，兼容性问题注明游戏版本和相关模组。
