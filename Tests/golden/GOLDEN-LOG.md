# Golden 基线刷新审计日志

> golden（`sample-idml.snapshot.txt`）是导出回归的最后一道网：刷错一次，之后的回归就会
> 带着错误基线继续「全绿」。因此每次刷新只能经 `scripts/golden-update.sh --reason "…"`
> 进行——脚本会强制打印新旧 diff、拒绝空刷，并在本文件留痕（时间 + 变化规模 + 原因）。
> 禁止手工覆盖基线文件。追加式，最新在最下方。

## 2026-07-07 之前 | （历史）
- 原因：护栏引入前的历史刷新未留痕，known 的有意刷新见 git log 中各 golden 相关提交
  （THREAD-1b 章级 Story 合并、MASTER-1 主页页码、TYPE-1 段末 NoBreak 等）。

## 2026-07-07 06:12 | 约 +0/-1 行
- 原因：自证测试：验证 diff 打印与留痕路径

