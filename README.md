# 绝地潜兵 2：C4 快速引爆

C4 Quick Detonation，当前版本 **1.0.0-rc1**。保留游戏原生左键投掷、扣弹和装填，右键远程引爆。

## 下载和安装

在本仓库 **Releases** 下载 `C4快速引爆-1.0.0-rc1-Release.zip`，通过 HD2 Mod Manager 导入、启用并部署。需要 Bingus Shared Loader v17 或更新版本。先停用参考版以及 M1/M1.2/M1.3 等旧 C4 控制器。

使用默认左/右鼠标绑定。拿出 C4、完成装备动作并松开双键后接管；模式偏离时会在空闲双键释放期间自动校正 DEPLOY。切枪过渡阶段取消尚未提交的引爆。

站立空闲时仅调用原生引爆动作取得按压反馈；投掷收尾或装填期间仅走直接引爆以保留速度，此时没有额外按压动画。Diagnostic 只供故障定位，和 Release 二选一。

**这是尚待实机验收的候选版。** 离线检查和独立源码复现已通过；本版本的实际动画、自动模式、切枪边界、性能、长期弹药及多人兼容性尚未验证。

- [安装与卸载](outputs/正式交付/安装与卸载.md)
- [发布说明](outputs/正式交付/发布说明.md)
- [短实机验收](outputs/正式交付/短实机验收.md)
- [离线验证](outputs/正式交付/离线验证.json)

## 构建

需要 Python 3.10 或更新版本，不依赖外部 Python 包：

```powershell
python -B work/日用版源码/build.py
```

输出到 `outputs/正式交付`，不会部署或启动游戏。保持现有目录结构以复用已验证的构建链。公开源码中的 native catalog 已将被 mask 忽略的字节归零；不发布原始游戏模块、进程转储或实测日志。

离线回归还需 Windows x64 与本机合法安装游戏中的 LuaJIT DLL：

```powershell
python -B work/日用版源码/check.py
```

`check.py` 中的 DLL 路径需按本机安装位置调整；它在隔离进程执行合成测试，不启动游戏或调用游戏原生动作。`evidence.py` 是原工作区历史审计工具，依赖未上传的旧日志和旧构建，不属于必需构建步骤。

## 目录与授权

- `work/日用版源码`：本候选版的逻辑、构建和回归测试。
- `work/上游源码`：复用的基础模块、签名目录和合成测试工具。
- `参考mod/BingusSharedLoader-main/scripts`：打包所需的 Loader 工具。
- `outputs`：构建规格和交付说明。

项目沿用 MIT License；Loader 打包工具保留其 Zero-Clause BSD License。具体归属见 [NOTICE.md](NOTICE.md) 与对应 LICENSE。此项目与游戏开发商无隶属关系。
