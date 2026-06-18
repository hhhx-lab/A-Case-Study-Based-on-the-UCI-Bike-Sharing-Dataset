# 基于 UCI Bike Sharing Dataset 的 R 语言统计分析

本仓库为《统计软件》课程论文的配套项目，围绕 UCI Machine Learning Repository 的 Bike Sharing Dataset，使用 R 语言分析共享单车租赁需求的时间规律、天气影响、用户差异和预测模型表现。

论文最终稿已放在 `paper/` 目录，核心分析代码为 `scripts/analysis.R`。

## 研究主题

论文题目：

> 基于 R 语言的共享单车租赁需求影响因素与预测分析：以 UCI Bike Sharing Dataset 为例

研究重点包括：

- 数据质量检查与变量转换
- 描述性统计与探索性可视化
- 工作日、季节、天气等因素的统计推断
- 线性回归、负二项回归与模型诊断
- LASSO、回归树、随机森林等预测模型比较
- 休闲用户与注册用户的差异分析

## 仓库结构

```text
.
|-- README.md
|-- bike_sharing_dataset/
|   |-- Readme.txt
|   |-- day.csv
|   `-- hour.csv
|-- paper/
|   |-- paper.docx
|   `-- paper.pdf
`-- scripts/
    `-- analysis.R
```

## 文件说明

| 路径 | 说明 |
|---|---|
| `bike_sharing_dataset/` | UCI Bike Sharing Dataset 原始数据 |
| `scripts/analysis.R` | R 分析主脚本 |
| `paper/paper.docx` | 最终 Word 论文 |
| `paper/paper.pdf` | 最终 PDF 论文 |

## 运行环境

建议使用 R 4.5 或更高版本。主要 R 包包括：

```r
readr, dplyr, tidyr, ggplot2, lubridate, scales,
broom, MASS, rpart, janitor, skimr, psych,
GGally, corrplot, patchwork, rstatix, modelsummary, gt,
car, lmtest, sandwich, rsample, yardstick, recipes,
parsnip, workflows, ranger, vip, glmnet
```

## 复现分析

在项目根目录运行：

```bash
Rscript scripts/analysis.R
```

脚本会基于 `bike_sharing_dataset/` 中的原始 CSV 数据重新生成统计表、图像、模型对象和分析日志。这些运行结果默认输出到本地 `outputs/` 目录。

## 数据来源

数据集来源：

Fanaee-T, H. Bike Sharing Dataset. UCI Machine Learning Repository. https://doi.org/10.24432/C5W894

相关论文：

Fanaee-T, H., and Gama, J. Event labeling combining ensemble detectors and background knowledge. Progress in Artificial Intelligence, 2013, 2(2-3), 113-127.

## 说明

仓库仅保留论文最终稿、原始数据和可复现分析代码。`outputs/` 为本地运行生成目录，不作为公开仓库的必要内容。
