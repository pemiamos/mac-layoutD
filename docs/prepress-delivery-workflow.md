# 印前交付流程：LayoutD RGB PDF → Acrobat → 印厂级 CMYK PDF/X

> **路线更新（2026-06-19，见 `.ai/DECISIONS.md`）**：主交付路线已转为
> **LayoutD 导出 IDML → InDesign 人工精调 + 印前输出**。届时 CMYK 分色 / PDF/X
> 合规直接在 InDesign 里完成，本文「RGB PDF → Acrobat」流程作为 **不经 InDesign 的
> 直出备选路径** 保留（例如只需快速出一版印厂稿、或暂未接入 IDML 时）。两条路线都
> 不在 LayoutD 内自建 CMYK 色彩管线（印前路线 A 不变）。
>
> 适用范围：用 LayoutD 排版中文科普图书，需要交付印厂正式印刷时（不走 InDesign 的备选路径）。
> 设计前提（路线 A）：LayoutD 渲染管线为 **RGB**，不内建 CMYK 分色；CMYK 转色与
> PDF/X 合规由 **Acrobat Pro** 在交付前一步完成。

## 分工一句话

**LayoutD 负责把文件做「干净」（预检），Acrobat 负责最后一公里「转色 + 合规」。**
两者缺一不可——Acrobat 补不了源文件本身缺的东西（出血、专色、分辨率）。

---

## 第 0 步：先问印厂三件事（最重要，别拍脑袋）

CMYK 转换结果取决于目标配置，选错等于白转。开印前先问清：

1. **目标 ICC 配置文件**？常见：
   - 日本印厂 / 涂布纸：`Japan Color 2001 Coated`
   - 欧洲：`FOGRA39 (PSO Coated)`
   - 美国：`GRACoL 2006 / US Web Coated (SWOP)`
   - 非涂布纸（胶版纸/书纸）：对应的 Uncoated 版本
2. **PDF/X 版本**？`PDF/X-1a`（最保守，纯 CMYK + 扁平化，兼容性最好）或
   `PDF/X-4`（保留透明，更现代）。中文科普书一般 **X-1a** 即可。
3. **总墨量上限（TAC）+ 谁来转**？很多印厂**更愿意自己转**，或有特定墨量要求。
   先问能省掉双重转换和返工。

---

## 第 1 步：LayoutD 侧——把文件做干净

1. **页面设置**：出血设为常规 **3 mm**（印厂另有要求则按印厂）。
2. **导出 PDF**：勾选「**添加印刷裁切线及出血标记**」。
3. **清空印前预检警告**：看右侧 Inspector「排版问题检查 → 印前」分类，逐条处理。
   这些是 Acrobat **补不了**、必须在 LayoutD 阶段解决的：
   - 出血 = 0 → 满版图/背景没延伸到出血框，成品会露白
   - 置入图 effectiveDPI < 300 → 分辨率不够，Acrobat 不会帮你放大
   - 字体不可嵌 / 系统缺失 → 授权或替换字体
   - 发丝线（< 0.25pt）→ 加粗

> 预检干净 = 交给 Acrobat 的是「好坯子」，转出来才干净。

---

## 第 2 步：Acrobat Pro 转 PDF/X

需要 **Acrobat Pro**（非 Reader；有 Distiller 即为 Pro）。

1. `印刷制作 (Print Production) → 印刷预检 (Preflight)`
2. 选 **「转换为 PDF/X-1a」**（或印厂指定版本）的 Profile
3. 在 Profile 设置里把**目标 ICC 配置**改成印厂给的那个
4. 运行 → Acrobat 会同时：RGB→CMYK 转色、嵌入输出意图、强制 PDF/X 合规，并列出无法自动修的问题
5. 修掉报告里的问题 → 另存

---

## 第 3 步：⭐ 中文正文必须是纯黑（K=100, CMY=0）——必须专门处理

**这是中文转 CMYK 的头号坑，默认转换会「制造」这个问题。**

**为什么**：朴素的 ICC RGB→CMYK 转换会把 RGB 黑 `(0,0,0)` 映射成**四色叠加的「富黑」**
（如 C72 M68 Y67 K90），而**不是**纯 K=100。中文笔画细密，富黑文字一旦印刷套准
有微小偏差，每个笔画边缘就会出现彩色重影——小字尤其灾难。**正文黑字必须只走 K 版。**

**怎么解决**（Acrobat 里两选一）：

- **Convert Colors 时勾「保留黑色 / Preserve Black」**：源里的纯黑（RGB 0,0,0 /
  灰度黑 / K-only）会保持为 K-only，不被转成富黑。
- 或用 **Preflight 修正项（Fixup）**：搜 "black" 类修正，把 RGB/灰度黑强制转为
  「仅黑版 (K-only)」。

**前提**：LayoutD 正文黑字是真 `#000000`（是的），勾了保留黑色就会落到 K=100。

**必须验证**（别凭感觉）：
`印刷制作 → 输出预览 (Output Preview) → 分色 (Separations)`
- 把鼠标移到正文黑字上 → 读数应为 **C0 M0 Y0 K100**
- 或单独关掉 C/M/Y 三个版，只留 K 版 → 正文文字应**只在 K 版上可见**

> 小结：**会担心 → 但一个「保留黑色」选项 + 输出预览验证就能搞定。** 关键是别用
> 默认设置直接转、转完不检查。

---

## 第 4 步：验证合规 + 交付

1. **PDF/X 合规复检**：Preflight 跑一遍「验证 PDF/X 合规性」Profile，应全过。
2. **分色检查**：Output Preview 看 TAC 总墨量是否超印厂上限、正文是否 K-only。
3. **交印厂**：最好让印厂出一张**数码打样 / 合同样**确认颜色，再批量开印。

---

## 附：Acrobat 能修 vs 修不了

| Acrobat Pro 能做 | 必须 LayoutD 阶段就对（Acrobat 救不了） |
|---|---|
| RGB→CMYK 转色（按 ICC） | 出血像素：源里没画到出血框，变不出来 |
| 嵌入输出意图、定 PDF/X 版本 | 专色 Pantone：RGB 源里没有就生不出 |
| 扁平化透明、嵌字体（可嵌的） | 低分辨率图：不会把 150dpi 变 300dpi |
| 设 TrimBox / BleedBox | 正文需为 K-only：靠转换设置保证（见第 3 步） |

---

## 一页速查

```
印厂确认：目标 ICC？PDF/X 版本？墨量上限？要不要他们自己转？
   ↓
LayoutD：出血 3mm + 裁切线 + 清空印前预检警告 → 导出 RGB PDF
   ↓
Acrobat Pro：Preflight「转换为 PDF/X-1a」+ 目标 ICC + 勾「保留黑色」
   ↓
验证：Output Preview 分色 → 正文 K100/CMY0？TAC 没超？PDF/X 合规过？
   ↓
交印厂：先要数码打样/合同样确认颜色 → 批量
```
