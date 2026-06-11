# 基于 UCI Bike Sharing Dataset 的 R 语言统计分析论文

本项目为《统计软件》课程论文配套工程，基于 UCI Machine Learning Repository 的 Bike Sharing Dataset，使用 R 完成共享单车租赁需求的数据清洗、描述统计、可视化、统计推断、回归诊断、计数模型、机器学习预测和用户类型差异分析，并生成最终 Word/PDF 论文。

## 项目结构

| 路径 | 说明 |
|---|---|
| `bike_sharing_dataset/` | UCI Bike Sharing Dataset 原始数据 |
| `scripts/analysis.R` | R 分析主脚本，生成表格、图像、模型和日志 |
| `scripts/build_final_docx.py` | 最终 DOCX 生成脚本 |
| `outputs/tables/` | R 输出的统计表、检验表和模型结果 |
| `outputs/figures/` | R 输出的可视化图片 |
| `outputs/models/` | R 保存的模型对象 |
| `docs/` | 论文计划、方法说明、理论基础和格式检查文档 |
| `paper/paper.docx` | 最终 Word 论文 |
| `paper/paper.pdf` | 最终 PDF 论文 |

## 复现方式

1. 在项目根目录运行 R 分析脚本：

   ```bash
   Rscript scripts/analysis.R
   ```

2. 生成最终 Word 论文：

   ```bash
   python scripts/build_final_docx.py
   ```

3. 将 Word 转为 PDF：

   ```bash
   codex-docx-to-pdf paper/paper.docx paper
   ```

## 说明

论文正文和附录中涉及的项目文件均使用相对路径。附录 C 中，附图已真实插入；附表以相对路径、行列规模和代表性预览形式写入，完整表格文件保存在 `outputs/tables/`。
