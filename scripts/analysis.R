#!/usr/bin/env Rscript

# Bike Sharing thesis analysis pipeline.
# Run from the project root: .

options(stringsAsFactors = FALSE)
set.seed(20260608)

required <- c(
  "readr", "dplyr", "tidyr", "ggplot2", "lubridate", "scales",
  "broom", "MASS", "rpart", "knitr", "janitor", "skimr", "psych",
  "GGally", "corrplot", "patchwork", "rstatix", "modelsummary", "gt",
  "car", "lmtest", "sandwich", "rsample", "yardstick", "recipes",
  "parsnip", "workflows", "ranger", "vip", "glmnet"
)
missing_required <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_required) > 0) {
  stop("Missing required R packages: ", paste(missing_required, collapse = ", "))
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(lubridate)
  library(scales)
  library(broom)
  library(rpart)
  library(janitor)
})

project_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
data_dir <- file.path(project_dir, "bike_sharing_dataset")
output_dir <- file.path(project_dir, "outputs")
fig_dir <- file.path(output_dir, "figures")
table_dir <- file.path(output_dir, "tables")
model_dir <- file.path(output_dir, "models")
paper_dir <- file.path(project_dir, "paper")

dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(paper_dir, recursive = TRUE, showWarnings = FALSE)

theme_paper <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}

save_plot <- function(plot, filename, width = 8, height = 5) {
  ggsave(
    filename = file.path(fig_dir, filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300
  )
}

write_table <- function(data, filename) {
  readr::write_csv(data, file.path(table_dir, filename), na = "")
}

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), NA_character_, formatC(x, format = "f", digits = digits))
}

metric_rmse <- function(truth, estimate) sqrt(mean((truth - estimate)^2, na.rm = TRUE))
metric_mae <- function(truth, estimate) mean(abs(truth - estimate), na.rm = TRUE)
metric_r2 <- function(truth, estimate) {
  1 - sum((truth - estimate)^2, na.rm = TRUE) / sum((truth - mean(truth, na.rm = TRUE))^2, na.rm = TRUE)
}

safe_p <- function(x) {
  ifelse(is.na(x), NA_character_, ifelse(x < 0.001, "<0.001", fmt(x, 4)))
}

sink(file.path(output_dir, "analysis_log.txt"), split = TRUE)
cat("Bike Sharing thesis analysis\n")
cat("Project directory:", project_dir, "\n")
cat("Run time:", as.character(Sys.time()), "\n\n")

cat("Package availability\n")
optional_packages <- c("tidymodels")
package_table <- tibble(
  package = c(required, optional_packages),
  available = vapply(c(required, optional_packages), requireNamespace, logical(1), quietly = TRUE)
)
print(package_table)
write_table(package_table, "table00_package_availability.csv")

# 1. Read data ---------------------------------------------------------------
bike_hour_raw <- read_csv(file.path(data_dir, "hour.csv"), show_col_types = FALSE)
bike_day_raw <- read_csv(file.path(data_dir, "day.csv"), show_col_types = FALSE)

cat("\nRaw data dimensions\n")
print(dim(bike_hour_raw))
print(dim(bike_day_raw))

# 2. Quality checks ----------------------------------------------------------
dataset_overview <- tibble(
  dataset = c("hour.csv", "day.csv"),
  observations = c(nrow(bike_hour_raw), nrow(bike_day_raw)),
  variables = c(ncol(bike_hour_raw), ncol(bike_day_raw)),
  start_date = c(min(bike_hour_raw$dteday), min(bike_day_raw$dteday)),
  end_date = c(max(bike_hour_raw$dteday), max(bike_day_raw$dteday)),
  role = c("主分析数据：小时级租赁记录", "补充分析数据：日级租赁记录")
)
write_table(dataset_overview, "table01_dataset_overview.csv")

variable_dictionary <- tibble(
  variable = c("instant", "dteday", "season", "yr", "mnth", "hr", "holiday", "weekday", "workingday", "weathersit", "temp", "atemp", "hum", "windspeed", "casual", "registered", "cnt"),
  meaning = c(
    "记录编号",
    "日期",
    "季节，1 春季、2 夏季、3 秋季、4 冬季",
    "年份，0 为 2011 年、1 为 2012 年",
    "月份，1 至 12",
    "小时，0 至 23",
    "是否节假日",
    "星期",
    "是否工作日",
    "天气状况",
    "标准化气温，除以 41",
    "标准化体感温度，除以 50",
    "标准化湿度，除以 100",
    "标准化风速，除以 67",
    "休闲用户租赁量",
    "注册用户租赁量",
    "总租赁量"
  ),
  analysis_role = c(
    "索引，不参与建模",
    "日期处理",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "分类解释变量",
    "连续解释变量",
    "相关性说明，不进入主模型",
    "连续解释变量",
    "连续解释变量",
    "用户差异分析因变量",
    "用户差异分析因变量",
    "主要因变量"
  )
)
write_table(variable_dictionary, "table02_variable_dictionary.csv")

missing_table <- bike_hour_raw |>
  summarise(across(everything(), ~ sum(is.na(.x)))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "missing_count") |>
  mutate(missing_rate = missing_count / nrow(bike_hour_raw))
write_table(missing_table, "table03_missing_values.csv")

duplicate_count <- sum(duplicated(bike_hour_raw))
instant_duplicate_count <- nrow(bike_hour_raw) - n_distinct(bike_hour_raw$instant)
cnt_identity_failures <- sum(bike_hour_raw$casual + bike_hour_raw$registered != bike_hour_raw$cnt)

quality_checks <- tibble(
  check_item = c("完全重复记录", "instant 重复编号", "cnt = casual + registered 不成立记录", "hour.csv 缺失值总数"),
  value = c(duplicate_count, instant_duplicate_count, cnt_identity_failures, sum(missing_table$missing_count)),
  conclusion = c("未发现完全重复记录", "记录编号唯一", "总租赁量组成关系全部成立", "未发现缺失值")
)
write_table(quality_checks, "table04_quality_checks.csv")

# 3. Transform variables -----------------------------------------------------
bike_hour <- bike_hour_raw |>
  mutate(
    date = ymd(dteday),
    season_code = season,
    weather_code = weathersit,
    year_num = if_else(yr == 0, 2011L, 2012L),
    hour_num = hr,
    month_num = mnth,
    weekday_num = weekday,
    season = factor(season, levels = c(1, 2, 3, 4), labels = c("春季", "夏季", "秋季", "冬季")),
    yr = factor(yr, levels = c(0, 1), labels = c("2011年", "2012年")),
    mnth = factor(mnth, levels = 1:12, labels = paste0(1:12, "月")),
    hr = factor(hr, levels = 0:23, labels = paste0(0:23, "时")),
    holiday = factor(holiday, levels = c(0, 1), labels = c("非节假日", "节假日")),
    weekday = factor(weekday, levels = 0:6, labels = c("周日", "周一", "周二", "周三", "周四", "周五", "周六")),
    workingday = factor(workingday, levels = c(0, 1), labels = c("非工作日", "工作日")),
    weathersit = factor(weathersit, levels = c(1, 2, 3, 4), labels = c("晴朗或少云", "多云或有雾", "小雨雪", "恶劣天气")),
    temp_celsius = temp * 41,
    atemp_celsius = atemp * 50,
    hum_percent = hum * 100,
    windspeed_real = windspeed * 67,
    cnt_log = log1p(cnt),
    casual_ratio = casual / cnt,
    registered_ratio = registered / cnt,
    hour_group = case_when(
      hour_num >= 0 & hour_num <= 5 ~ "凌晨",
      hour_num >= 6 & hour_num <= 9 ~ "早高峰",
      hour_num >= 10 & hour_num <= 15 ~ "日间",
      hour_num >= 16 & hour_num <= 19 ~ "晚高峰",
      TRUE ~ "夜间"
    ),
    hour_group = factor(hour_group, levels = c("凌晨", "早高峰", "日间", "晚高峰", "夜间"))
  )

bike_day <- bike_day_raw |>
  mutate(
    date = ymd(dteday),
    year_num = if_else(yr == 0, 2011L, 2012L),
    month_num = mnth,
    season = factor(season, levels = c(1, 2, 3, 4), labels = c("春季", "夏季", "秋季", "冬季")),
    yr = factor(yr, levels = c(0, 1), labels = c("2011年", "2012年")),
    mnth = factor(mnth, levels = 1:12, labels = paste0(1:12, "月")),
    temp_celsius = temp * 41,
    hum_percent = hum * 100,
    windspeed_real = windspeed * 67
  )

write_rds(bike_hour, file.path(output_dir, "bike_hour_processed.rds"))
write_rds(bike_day, file.path(output_dir, "bike_day_processed.rds"))

# 4. Descriptive statistics --------------------------------------------------
desc_vars <- bike_hour |>
  select(cnt, casual, registered, temp_celsius, atemp_celsius, hum_percent, windspeed_real)

desc_table <- desc_vars |>
  summarise(
    across(
      everything(),
      list(
        n = ~ sum(!is.na(.x)),
        mean = ~ mean(.x, na.rm = TRUE),
        sd = ~ sd(.x, na.rm = TRUE),
        min = ~ min(.x, na.rm = TRUE),
        q1 = ~ as.numeric(quantile(.x, 0.25, na.rm = TRUE)),
        median = ~ median(.x, na.rm = TRUE),
        q3 = ~ as.numeric(quantile(.x, 0.75, na.rm = TRUE)),
        max = ~ max(.x, na.rm = TRUE)
      ),
      .names = "{.col}__{.fn}"
    )
  ) |>
  pivot_longer(everything(), names_to = "name", values_to = "value") |>
  separate(name, into = c("variable", "stat"), sep = "__") |>
  pivot_wider(names_from = stat, values_from = value) |>
  mutate(
    variable_cn = recode(
      variable,
      cnt = "总租赁量",
      casual = "休闲用户租赁量",
      registered = "注册用户租赁量",
      temp_celsius = "气温（摄氏度）",
      atemp_celsius = "体感温度（摄氏度）",
      hum_percent = "湿度（%）",
      windspeed_real = "风速"
    )
  ) |>
  select(variable, variable_cn, n, mean, sd, min, q1, median, q3, max)
write_table(desc_table, "table05_descriptive_stats.csv")

skim_output <- skimr::skim(bike_hour)
write_table(as.data.frame(skim_output), "table05b_skimr_overview.csv")

psych_desc <- psych::describe(desc_vars) |>
  as.data.frame() |>
  tibble::rownames_to_column("variable")
write_table(psych_desc, "table05c_psych_describe.csv")

factor_distribution <- bind_rows(
  bike_hour |> count(season, name = "n") |> mutate(variable = "season", category = as.character(season)) |> select(variable, category, n),
  bike_hour |> count(yr, name = "n") |> mutate(variable = "yr", category = as.character(yr)) |> select(variable, category, n),
  bike_hour |> count(workingday, name = "n") |> mutate(variable = "workingday", category = as.character(workingday)) |> select(variable, category, n),
  bike_hour |> count(holiday, name = "n") |> mutate(variable = "holiday", category = as.character(holiday)) |> select(variable, category, n),
  bike_hour |> count(weathersit, name = "n") |> mutate(variable = "weathersit", category = as.character(weathersit)) |> select(variable, category, n)
) |>
  group_by(variable) |>
  mutate(percent = n / sum(n)) |>
  ungroup()
write_table(factor_distribution, "table06_factor_distribution.csv")

group_means <- bind_rows(
  bike_hour |> group_by(season) |> summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), .groups = "drop") |> mutate(group_variable = "season", group = as.character(season)) |> select(group_variable, group, n, mean_cnt, median_cnt),
  bike_hour |> group_by(yr) |> summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), .groups = "drop") |> mutate(group_variable = "yr", group = as.character(yr)) |> select(group_variable, group, n, mean_cnt, median_cnt),
  bike_hour |> group_by(workingday) |> summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), .groups = "drop") |> mutate(group_variable = "workingday", group = as.character(workingday)) |> select(group_variable, group, n, mean_cnt, median_cnt),
  bike_hour |> group_by(weathersit) |> summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), .groups = "drop") |> mutate(group_variable = "weathersit", group = as.character(weathersit)) |> select(group_variable, group, n, mean_cnt, median_cnt)
)
write_table(group_means, "table07_group_means.csv")

hour_summary <- bike_hour |>
  group_by(hour_num) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), mean_casual = mean(casual), mean_registered = mean(registered), .groups = "drop")
write_table(hour_summary, "table08_hour_summary.csv")

month_summary <- bike_hour |>
  group_by(month_num, mnth) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), .groups = "drop")
write_table(month_summary, "table09_month_summary.csv")

# 5. Figures -----------------------------------------------------------------
p_cnt_dist <- ggplot(bike_hour, aes(x = cnt)) +
  geom_histogram(bins = 50, fill = "#3B82F6", color = "white") +
  geom_density(aes(y = after_stat(count)), color = "#DC2626", linewidth = 0.8) +
  labs(title = "总租赁量分布", x = "每小时总租赁量", y = "频数") +
  theme_paper()
save_plot(p_cnt_dist, "fig01_cnt_distribution.png")

user_long <- bike_hour |>
  select(casual, registered, cnt) |>
  pivot_longer(everything(), names_to = "user_type", values_to = "rentals") |>
  mutate(user_type = recode(user_type, casual = "休闲用户", registered = "注册用户", cnt = "总租赁量"))
p_user_dist <- ggplot(user_long, aes(x = rentals, fill = user_type)) +
  geom_histogram(bins = 50, color = "white") +
  facet_wrap(~ user_type, scales = "free_y") +
  labs(title = "不同用户类型租赁量分布", x = "每小时租赁量", y = "频数") +
  theme_paper() +
  theme(legend.position = "none")
save_plot(p_user_dist, "fig02_user_distribution.png", width = 9, height = 5)

p_hourly <- ggplot(hour_summary, aes(x = hour_num, y = mean_cnt)) +
  geom_line(color = "#2563EB", linewidth = 1) +
  geom_point(color = "#2563EB", size = 2) +
  scale_x_continuous(breaks = 0:23) +
  labs(title = "不同小时的平均共享单车租赁量", x = "小时", y = "平均租赁量") +
  theme_paper()
save_plot(p_hourly, "fig03_hourly_pattern.png", width = 9, height = 5)

working_hour_summary <- bike_hour |>
  group_by(workingday, hour_num) |>
  summarise(mean_cnt = mean(cnt), .groups = "drop")
p_working_hour <- ggplot(working_hour_summary, aes(x = hour_num, y = mean_cnt, color = workingday)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.6) +
  scale_x_continuous(breaks = 0:23) +
  labs(title = "工作日与非工作日的小时租赁模式比较", x = "小时", y = "平均租赁量", color = "日期类型") +
  theme_paper()
save_plot(p_working_hour, "fig04_workingday_hour_pattern.png", width = 9, height = 5)

p_month <- ggplot(month_summary, aes(x = month_num, y = mean_cnt)) +
  geom_line(color = "#059669", linewidth = 1) +
  geom_point(color = "#059669", size = 2) +
  scale_x_continuous(breaks = 1:12) +
  labs(title = "不同月份的平均租赁量", x = "月份", y = "平均租赁量") +
  theme_paper()
save_plot(p_month, "fig05_monthly_pattern.png")

p_season <- ggplot(bike_hour, aes(x = season, y = cnt, fill = season)) +
  geom_boxplot(alpha = 0.85, outlier.alpha = 0.25) +
  labs(title = "不同季节的租赁量分布", x = "季节", y = "每小时总租赁量") +
  theme_paper() +
  theme(legend.position = "none")
save_plot(p_season, "fig06_season_boxplot.png")

weekday_hour <- bike_hour |>
  group_by(weekday, hour_num) |>
  summarise(mean_cnt = mean(cnt), .groups = "drop")
p_heatmap <- ggplot(weekday_hour, aes(x = hour_num, y = weekday, fill = mean_cnt)) +
  geom_tile(color = "white") +
  scale_x_continuous(breaks = 0:23) +
  scale_fill_viridis_c(option = "C") +
  labs(title = "星期与小时维度下的平均租赁量热力图", x = "小时", y = "星期", fill = "平均租赁量") +
  theme_paper()
save_plot(p_heatmap, "fig07_weekday_hour_heatmap.png", width = 9, height = 5)

p_weather <- ggplot(bike_hour, aes(x = weathersit, y = cnt, fill = weathersit)) +
  geom_boxplot(alpha = 0.85, outlier.alpha = 0.25) +
  labs(title = "不同天气状况下的租赁量分布", x = "天气状况", y = "每小时总租赁量") +
  theme_paper() +
  theme(legend.position = "none")
save_plot(p_weather, "fig08_weather_boxplot.png")

p_temp <- ggplot(bike_hour, aes(x = temp_celsius, y = cnt)) +
  geom_point(alpha = 0.15, color = "#2563EB") +
  geom_smooth(method = "loess", se = TRUE, color = "#DC2626") +
  labs(title = "气温与总租赁量关系", x = "气温（摄氏度）", y = "每小时总租赁量") +
  theme_paper()
save_plot(p_temp, "fig09_temp_cnt_smooth.png")

p_hum <- ggplot(bike_hour, aes(x = hum_percent, y = cnt)) +
  geom_point(alpha = 0.15, color = "#0F766E") +
  geom_smooth(method = "loess", se = TRUE, color = "#DC2626") +
  labs(title = "湿度与总租赁量关系", x = "湿度（%）", y = "每小时总租赁量") +
  theme_paper()
save_plot(p_hum, "fig10_humidity_cnt_smooth.png")

p_wind <- ggplot(bike_hour, aes(x = windspeed_real, y = cnt)) +
  geom_point(alpha = 0.15, color = "#7C3AED") +
  geom_smooth(method = "loess", se = TRUE, color = "#DC2626") +
  labs(title = "风速与总租赁量关系", x = "风速", y = "每小时总租赁量") +
  theme_paper()
save_plot(p_wind, "fig11_windspeed_cnt_smooth.png")

corr_data <- bike_hour |>
  select(cnt, casual, registered, temp_celsius, atemp_celsius, hum_percent, windspeed_real)
corr_long <- cor(corr_data, use = "complete.obs") |>
  as.data.frame() |>
  tibble::rownames_to_column("var1") |>
  pivot_longer(-var1, names_to = "var2", values_to = "correlation")
write_table(corr_long, "table10_correlation_long.csv")
p_corr <- ggplot(corr_long, aes(x = var1, y = var2, fill = correlation)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f", correlation)), size = 3) +
  scale_fill_gradient2(low = "#2563EB", mid = "white", high = "#DC2626", limits = c(-1, 1)) +
  labs(title = "连续变量相关系数热力图", x = NULL, y = NULL, fill = "相关系数") +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
save_plot(p_corr, "fig12_correlation_heatmap.png", width = 7, height = 6)

png(file.path(fig_dir, "fig12b_corrplot.png"), width = 2200, height = 1800, res = 300)
corrplot::corrplot(cor(corr_data, use = "complete.obs"), method = "color", type = "upper", addCoef.col = "black", tl.col = "black", tl.srt = 35)
dev.off()

p_pairs <- GGally::ggpairs(
  bike_hour |>
    select(cnt, temp_celsius, hum_percent, windspeed_real, casual_ratio),
  progress = FALSE
) +
  theme_paper()
save_plot(p_pairs, "fig12c_ggpairs_core_variables.png", width = 9, height = 9)

user_hour <- bike_hour |>
  group_by(hour_num) |>
  summarise(casual = mean(casual), registered = mean(registered), .groups = "drop") |>
  pivot_longer(c(casual, registered), names_to = "user_type", values_to = "mean_rentals") |>
  mutate(user_type = recode(user_type, casual = "休闲用户", registered = "注册用户"))
p_user_hour <- ggplot(user_hour, aes(x = hour_num, y = mean_rentals, color = user_type)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.6) +
  scale_x_continuous(breaks = 0:23) +
  labs(title = "休闲用户与注册用户的小时租赁模式", x = "小时", y = "平均租赁量", color = "用户类型") +
  theme_paper()
save_plot(p_user_hour, "fig13_user_hour_pattern.png", width = 9, height = 5)

user_working_hour <- bike_hour |>
  group_by(workingday, hour_num) |>
  summarise(casual = mean(casual), registered = mean(registered), .groups = "drop") |>
  pivot_longer(c(casual, registered), names_to = "user_type", values_to = "mean_rentals") |>
  mutate(user_type = recode(user_type, casual = "休闲用户", registered = "注册用户"))
p_user_working <- ggplot(user_working_hour, aes(x = hour_num, y = mean_rentals, color = workingday)) +
  geom_line(linewidth = 1) +
  facet_wrap(~ user_type, scales = "free_y") +
  scale_x_continuous(breaks = seq(0, 23, by = 2)) +
  labs(title = "不同日期类型下两类用户的小时租赁模式", x = "小时", y = "平均租赁量", color = "日期类型") +
  theme_paper()
save_plot(p_user_working, "fig14_user_workingday_pattern.png", width = 9, height = 5)

daily_trend <- bike_day |>
  arrange(date)
p_daily <- ggplot(daily_trend, aes(x = date, y = cnt)) +
  geom_line(color = "#334155", linewidth = 0.5) +
  geom_smooth(method = "loess", color = "#DC2626", se = FALSE) +
  labs(title = "日级租赁量时间趋势", x = "日期", y = "每日总租赁量") +
  theme_paper()
save_plot(p_daily, "fig15_daily_trend.png", width = 9, height = 5)

# 6. Inference ---------------------------------------------------------------
test_rows <- list()

working_summary <- bike_hour |>
  group_by(workingday) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), sd_cnt = sd(cnt), .groups = "drop")
write_table(working_summary, "table11_workingday_summary.csv")
t_working <- t.test(cnt ~ workingday, data = bike_hour)
w_working <- wilcox.test(cnt ~ workingday, data = bike_hour)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "工作日 vs 非工作日", method = "t 检验", statistic = unname(t_working$statistic), p_value = t_working$p.value)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "工作日 vs 非工作日", method = "Wilcoxon 秩和检验", statistic = unname(w_working$statistic), p_value = w_working$p.value)

season_summary <- bike_hour |>
  group_by(season) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), sd_cnt = sd(cnt), .groups = "drop")
write_table(season_summary, "table12_season_summary.csv")
anova_season <- aov(cnt ~ season, data = bike_hour)
kw_season <- kruskal.test(cnt ~ season, data = bike_hour)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "季节差异", method = "ANOVA", statistic = broom::tidy(anova_season)$statistic[1], p_value = broom::tidy(anova_season)$p.value[1])
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "季节差异", method = "Kruskal-Wallis 检验", statistic = unname(kw_season$statistic), p_value = kw_season$p.value)
write_table(broom::tidy(TukeyHSD(anova_season)), "table13_season_tukey.csv")

weather_summary <- bike_hour |>
  group_by(weathersit) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), sd_cnt = sd(cnt), .groups = "drop")
write_table(weather_summary, "table14_weather_summary.csv")
anova_weather <- aov(cnt ~ weathersit, data = bike_hour)
kw_weather <- kruskal.test(cnt ~ weathersit, data = bike_hour)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "天气状况差异", method = "ANOVA", statistic = broom::tidy(anova_weather)$statistic[1], p_value = broom::tidy(anova_weather)$p.value[1])
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "天气状况差异", method = "Kruskal-Wallis 检验", statistic = unname(kw_weather$statistic), p_value = kw_weather$p.value)

bike_weather3 <- bike_hour |> filter(weathersit != "恶劣天气")
anova_weather3 <- aov(cnt ~ weathersit, data = bike_weather3)
kw_weather3 <- kruskal.test(cnt ~ weathersit, data = bike_weather3)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "天气状况差异（剔除恶劣天气）", method = "ANOVA", statistic = broom::tidy(anova_weather3)$statistic[1], p_value = broom::tidy(anova_weather3)$p.value[1])
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "天气状况差异（剔除恶劣天气）", method = "Kruskal-Wallis 检验", statistic = unname(kw_weather3$statistic), p_value = kw_weather3$p.value)

year_summary <- bike_hour |>
  group_by(yr) |>
  summarise(n = n(), mean_cnt = mean(cnt), median_cnt = median(cnt), sd_cnt = sd(cnt), .groups = "drop")
write_table(year_summary, "table15_year_summary.csv")
t_year <- t.test(cnt ~ yr, data = bike_hour)
w_year <- wilcox.test(cnt ~ yr, data = bike_hour)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "2011 年 vs 2012 年", method = "t 检验", statistic = unname(t_year$statistic), p_value = t_year$p.value)
test_rows[[length(test_rows) + 1]] <- tibble(comparison = "2011 年 vs 2012 年", method = "Wilcoxon 秩和检验", statistic = unname(w_year$statistic), p_value = w_year$p.value)

infer_tests <- bind_rows(test_rows) |>
  mutate(p_value_display = safe_p(p_value), conclusion = if_else(p_value < 0.05, "在 5% 水平下显著", "在 5% 水平下不显著"))
write_table(infer_tests, "table16_inference_tests.csv")

cor_tests <- tibble(
  variable = c("temp_celsius", "hum_percent", "windspeed_real"),
  pearson = c(
    cor(bike_hour$cnt, bike_hour$temp_celsius, method = "pearson"),
    cor(bike_hour$cnt, bike_hour$hum_percent, method = "pearson"),
    cor(bike_hour$cnt, bike_hour$windspeed_real, method = "pearson")
  ),
  spearman = c(
    cor(bike_hour$cnt, bike_hour$temp_celsius, method = "spearman"),
    cor(bike_hour$cnt, bike_hour$hum_percent, method = "spearman"),
    cor(bike_hour$cnt, bike_hour$windspeed_real, method = "spearman")
  )
)
write_table(cor_tests, "table17_environment_correlations.csv")

# 7. Regression models -------------------------------------------------------
lm_base <- lm(
  cnt_log ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real,
  data = bike_hour
)
lm_interaction <- lm(
  cnt_log ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real + workingday:hr,
  data = bike_hour
)

write_table(tidy(lm_base, conf.int = TRUE), "table18_lm_base_coefficients.csv")
write_table(tidy(lm_interaction, conf.int = TRUE), "table19_lm_interaction_coefficients.csv")
model_glance <- bind_rows(
  glance(lm_base) |> mutate(model = "线性回归基准模型"),
  glance(lm_interaction) |> mutate(model = "线性回归交互项模型")
) |>
  select(model, everything())
write_table(model_glance, "table20_lm_model_fit.csv")

modelsummary::modelsummary(
  list("基准模型" = lm_base, "交互项模型" = lm_interaction),
  statistic = "({std.error})",
  stars = TRUE,
  output = file.path(table_dir, "table20b_lm_modelsummary.html")
)

coef_focus_terms <- c("yr2012年", "season夏季", "season秋季", "season冬季", "weathersit多云或有雾", "weathersit小雨雪", "weathersit恶劣天气", "temp_celsius", "hum_percent", "windspeed_real")
lm_focus <- tidy(lm_base, conf.int = TRUE) |>
  filter(term %in% coef_focus_terms) |>
  mutate(percent_change = (exp(estimate) - 1) * 100)
write_table(lm_focus, "table21_lm_focus_terms.csv")

robust_base <- lmtest::coeftest(lm_base, vcov = sandwich::vcovHC(lm_base, type = "HC3"))
robust_mat <- unclass(robust_base)
robust_base_table <- data.frame(
  term = rownames(robust_mat),
  estimate = robust_mat[, 1],
  robust_std_error = robust_mat[, 2],
  statistic = robust_mat[, 3],
  p_value = robust_mat[, 4],
  row.names = NULL,
  check.names = FALSE
)
robust_base_table <- robust_base_table |>
  mutate(percent_change = (exp(estimate) - 1) * 100)
write_table(robust_base_table, "table21b_lm_base_hc3_robust.csv")

robust_focus <- robust_base_table |>
  filter(term %in% coef_focus_terms)
write_table(robust_focus, "table21c_lm_focus_hc3_robust.csv")

bp_test <- lmtest::bptest(lm_base)
bp_table <- tibble(
  test = "Breusch-Pagan 异方差检验",
  statistic = unname(bp_test$statistic),
  p_value = bp_test$p.value,
  conclusion = if_else(bp_test$p.value < 0.05, "存在异方差迹象，使用 HC3 稳健标准误补充", "未发现显著异方差")
)
write_table(bp_table, "table21d_breusch_pagan_test.csv")

png(file.path(fig_dir, "fig16_lm_diagnostics.png"), width = 2400, height = 1800, res = 300)
par(mfrow = c(2, 2))
plot(lm_base)
dev.off()

vif_raw <- car::vif(lm_base)
if (is.matrix(vif_raw)) {
  vif_table <- as.data.frame(vif_raw) |>
    tibble::rownames_to_column("term") |>
    mutate(gvif_adjusted = GVIF^(1 / (2 * Df)))
} else {
  vif_table <- tibble(term = names(vif_raw), VIF = as.numeric(vif_raw), gvif_adjusted = as.numeric(vif_raw))
}
write_table(vif_table, "table22_lm_vif_car.csv")

# 8. Count models ------------------------------------------------------------
pois_model <- glm(
  cnt ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real,
  family = poisson(link = "log"),
  data = bike_hour
)
overdispersion_ratio <- sum(residuals(pois_model, type = "pearson")^2) / pois_model$df.residual
nb_model <- MASS::glm.nb(
  cnt ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real,
  data = bike_hour,
  control = glm.control(maxit = 100)
)

write_table(tidy(pois_model, conf.int = FALSE), "table23_poisson_coefficients.csv")
write_table(tidy(nb_model, conf.int = FALSE), "table24_negbin_coefficients.csv")
nb_irr_focus <- tidy(nb_model, conf.int = FALSE) |>
  filter(term %in% coef_focus_terms) |>
  mutate(incidence_rate_ratio = exp(estimate))
write_table(nb_irr_focus, "table24b_negbin_focus_irr.csv")
count_model_compare <- tibble(
  model = c("Poisson 回归", "负二项回归"),
  AIC = c(AIC(pois_model), AIC(nb_model)),
  BIC = c(BIC(pois_model), BIC(nb_model)),
  overdispersion_ratio = c(overdispersion_ratio, NA_real_)
)
write_table(count_model_compare, "table25_count_model_compare.csv")

modelsummary::modelsummary(
  list("Poisson 回归" = pois_model, "负二项回归" = nb_model),
  statistic = "({std.error})",
  stars = TRUE,
  output = file.path(table_dir, "table25b_count_modelsummary.html")
)

# 9. Prediction models -------------------------------------------------------
set.seed(20260608)
split <- rsample::initial_split(bike_hour, prop = 0.8, strata = cnt)
bike_train <- rsample::training(split)
bike_test <- rsample::testing(split)

predictor_formula <- cnt ~ season + yr + mnth + hr + holiday + workingday + weathersit +
  temp_celsius + hum_percent + windspeed_real

lm_pred_model <- lm(
  predictor_formula,
  data = bike_train
)
nb_pred_model <- MASS::glm.nb(
  predictor_formula,
  data = bike_train,
  control = glm.control(maxit = 100)
)
tree_model <- rpart(
  predictor_formula,
  data = bike_train,
  method = "anova",
  control = rpart.control(cp = 0.001, minsplit = 30, xval = 5)
)

rf_model <- ranger::ranger(
  predictor_formula,
  data = bike_train,
  num.trees = 500,
  mtry = 8,
  min.node.size = 10,
  importance = "permutation",
  seed = 20260608
)

x_train <- model.matrix(predictor_formula, data = bike_train)[, -1, drop = FALSE]
y_train <- bike_train$cnt
x_test <- model.matrix(predictor_formula, data = bike_test)[, -1, drop = FALSE]
missing_cols <- setdiff(colnames(x_train), colnames(x_test))
if (length(missing_cols) > 0) {
  x_test <- cbind(x_test, matrix(0, nrow = nrow(x_test), ncol = length(missing_cols), dimnames = list(NULL, missing_cols)))
}
x_test <- x_test[, colnames(x_train), drop = FALSE]
set.seed(20260608)
lasso_cv <- glmnet::cv.glmnet(x_train, y_train, alpha = 1, nfolds = 5, standardize = TRUE)

saveRDS(lm_pred_model, file.path(model_dir, "lm_prediction_model.rds"))
saveRDS(nb_pred_model, file.path(model_dir, "negbin_prediction_model.rds"))
saveRDS(tree_model, file.path(model_dir, "regression_tree_model.rds"))
saveRDS(rf_model, file.path(model_dir, "random_forest_model.rds"))
saveRDS(lasso_cv, file.path(model_dir, "lasso_cv_model.rds"))

predictions <- bike_test |>
  transmute(
    cnt,
    pred_lm = pmax(0, predict(lm_pred_model, newdata = bike_test)),
    pred_nb = pmax(0, predict(nb_pred_model, newdata = bike_test, type = "response")),
    pred_lasso = pmax(0, as.numeric(predict(lasso_cv, newx = x_test, s = "lambda.min"))),
    pred_rf = pmax(0, as.numeric(predict(rf_model, data = bike_test)$predictions)),
    pred_tree = pmax(0, predict(tree_model, newdata = bike_test))
  )
write_table(predictions, "table26_test_predictions.csv")

prediction_metrics <- tibble(
  model = c("线性回归", "负二项回归", "LASSO 回归", "随机森林", "回归树"),
  RMSE = c(
    metric_rmse(predictions$cnt, predictions$pred_lm),
    metric_rmse(predictions$cnt, predictions$pred_nb),
    metric_rmse(predictions$cnt, predictions$pred_lasso),
    metric_rmse(predictions$cnt, predictions$pred_rf),
    metric_rmse(predictions$cnt, predictions$pred_tree)
  ),
  MAE = c(
    metric_mae(predictions$cnt, predictions$pred_lm),
    metric_mae(predictions$cnt, predictions$pred_nb),
    metric_mae(predictions$cnt, predictions$pred_lasso),
    metric_mae(predictions$cnt, predictions$pred_rf),
    metric_mae(predictions$cnt, predictions$pred_tree)
  ),
  R_squared = c(
    metric_r2(predictions$cnt, predictions$pred_lm),
    metric_r2(predictions$cnt, predictions$pred_nb),
    metric_r2(predictions$cnt, predictions$pred_lasso),
    metric_r2(predictions$cnt, predictions$pred_rf),
    metric_r2(predictions$cnt, predictions$pred_tree)
  )
)
write_table(prediction_metrics, "table27_prediction_metrics.csv")

p_pred <- ggplot(predictions, aes(x = cnt, y = pred_rf)) +
  geom_point(alpha = 0.25, color = "#2563EB") +
  geom_abline(slope = 1, intercept = 0, color = "#DC2626", linewidth = 0.8) +
  labs(title = "测试集真实值与随机森林预测值对比", x = "真实总租赁量", y = "预测总租赁量") +
  theme_paper()
save_plot(p_pred, "fig17_rf_prediction_actual.png")

p_pred_models <- predictions |>
  select(cnt, pred_lm, pred_nb, pred_lasso, pred_rf, pred_tree) |>
  pivot_longer(-cnt, names_to = "model", values_to = "prediction") |>
  mutate(model = recode(model, pred_lm = "线性回归", pred_nb = "负二项回归", pred_lasso = "LASSO 回归", pred_rf = "随机森林", pred_tree = "回归树")) |>
  ggplot(aes(x = cnt, y = prediction)) +
  geom_point(alpha = 0.18, color = "#2563EB", size = 0.8) +
  geom_abline(slope = 1, intercept = 0, color = "#DC2626", linewidth = 0.5) +
  facet_wrap(~ model) +
  labs(title = "测试集多模型真实值与预测值比较", x = "真实总租赁量", y = "预测总租赁量") +
  theme_paper()
save_plot(p_pred_models, "fig17b_prediction_actual_all_models.png", width = 10, height = 7)

tree_importance <- as.data.frame(tree_model$variable.importance) |>
  tibble::rownames_to_column("variable") |>
  rename(importance = `tree_model$variable.importance`) |>
  arrange(desc(importance))
write_table(tree_importance, "table28_tree_variable_importance.csv")

rf_importance <- tibble(variable = names(rf_model$variable.importance), importance = as.numeric(rf_model$variable.importance)) |>
  arrange(desc(importance))
write_table(rf_importance, "table28b_rf_variable_importance.csv")

lasso_coef_mat <- as.matrix(coef(lasso_cv, s = "lambda.min"))
lasso_coef <- data.frame(
  term = rownames(lasso_coef_mat),
  coefficient = as.numeric(lasso_coef_mat[, 1]),
  row.names = NULL
) |>
  filter(coefficient != 0) |>
  arrange(desc(abs(coefficient)))
write_table(lasso_coef, "table28c_lasso_nonzero_coefficients.csv")

lasso_meta <- tibble(
  lambda_min = lasso_cv$lambda.min,
  lambda_1se = lasso_cv$lambda.1se,
  nonzero_terms_at_lambda_min = nrow(lasso_coef) - any(lasso_coef$term == "(Intercept)")
)
write_table(lasso_meta, "table28d_lasso_cv_summary.csv")

p_importance <- tree_importance |>
  slice_head(n = 12) |>
  mutate(variable = reorder(variable, importance)) |>
  ggplot(aes(x = variable, y = importance)) +
  geom_col(fill = "#0F766E") +
  coord_flip() +
  labs(title = "回归树变量重要性", x = "变量", y = "重要性") +
  theme_paper()
save_plot(p_importance, "fig18_tree_variable_importance.png", width = 8, height = 5)

p_rf_importance <- rf_importance |>
  slice_head(n = 12) |>
  mutate(variable = reorder(variable, importance)) |>
  ggplot(aes(x = variable, y = importance)) +
  geom_col(fill = "#0F766E") +
  coord_flip() +
  labs(title = "随机森林变量重要性", x = "变量", y = "重要性") +
  theme_paper()
save_plot(p_rf_importance, "fig18b_rf_variable_importance.png", width = 8, height = 5)

png(file.path(fig_dir, "fig18c_vip_rf_importance.png"), width = 2400, height = 1500, res = 300)
print(vip::vip(rf_model, num_features = 12) + labs(title = "随机森林变量重要性（vip）") + theme_paper())
dev.off()

png(file.path(fig_dir, "fig19_regression_tree.png"), width = 2600, height = 1800, res = 250)
plot(tree_model, uniform = TRUE, margin = 0.08)
text(tree_model, use.n = TRUE, cex = 0.7)
dev.off()

# 10. User segment analysis --------------------------------------------------
user_share_summary <- bike_hour |>
  summarise(
    total_casual = sum(casual),
    total_registered = sum(registered),
    total_cnt = sum(cnt),
    casual_share = total_casual / total_cnt,
    registered_share = total_registered / total_cnt,
    mean_casual_ratio = mean(casual_ratio),
    mean_registered_ratio = mean(registered_ratio)
  )
write_table(user_share_summary, "table29_user_share_summary.csv")

user_season <- bike_hour |>
  group_by(season) |>
  summarise(mean_casual = mean(casual), mean_registered = mean(registered), casual_share = sum(casual) / sum(cnt), .groups = "drop")
write_table(user_season, "table30_user_season_summary.csv")

user_weather <- bike_hour |>
  group_by(weathersit) |>
  summarise(n = n(), mean_casual = mean(casual), mean_registered = mean(registered), casual_share = sum(casual) / sum(cnt), .groups = "drop")
write_table(user_weather, "table31_user_weather_summary.csv")

lm_casual <- lm(
  log1p(casual) ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real,
  data = bike_hour
)
lm_registered <- lm(
  log1p(registered) ~ season + yr + mnth + hr + holiday + workingday + weathersit +
    temp_celsius + hum_percent + windspeed_real,
  data = bike_hour
)
user_model_fit <- bind_rows(
  glance(lm_casual) |> mutate(model = "休闲用户 log1p(casual)"),
  glance(lm_registered) |> mutate(model = "注册用户 log1p(registered)")
) |>
  select(model, everything())
write_table(user_model_fit, "table32_user_model_fit.csv")

user_focus <- bind_rows(
  tidy(lm_casual, conf.int = TRUE) |> filter(term %in% coef_focus_terms) |> mutate(model = "休闲用户"),
  tidy(lm_registered, conf.int = TRUE) |> filter(term %in% coef_focus_terms) |> mutate(model = "注册用户")
) |>
  mutate(percent_change = (exp(estimate) - 1) * 100) |>
  select(model, everything())
write_table(user_focus, "table33_user_model_focus_terms.csv")

# 11. Result summary for paper ----------------------------------------------
best_model <- prediction_metrics |> arrange(RMSE) |> slice(1)
top_tree_vars <- paste(head(tree_importance$variable, 5), collapse = "、")
top_rf_vars <- paste(head(rf_importance$variable, 5), collapse = "、")
lasso_nonzero_n <- lasso_meta$nonzero_terms_at_lambda_min[1]

result_summary <- tibble(
  item = c(
    "hour_rows",
    "hour_variables",
    "day_rows",
    "cnt_mean",
    "cnt_median",
    "cnt_max",
    "casual_mean",
    "registered_mean",
    "season_lowest_mean",
    "season_highest_mean",
    "weather_best_mean",
    "weather_bad_mean",
    "year_2011_mean",
    "year_2012_mean",
    "peak_hour",
    "peak_hour_mean",
    "lowest_hour",
    "lowest_hour_mean",
    "workingday_mean",
    "nonworkingday_mean",
    "poisson_overdispersion",
    "poisson_AIC",
    "negbin_AIC",
    "best_prediction_model",
    "best_prediction_RMSE",
    "best_prediction_MAE",
    "best_prediction_R2",
    "top_tree_variables",
    "top_rf_variables",
    "lasso_nonzero_terms",
    "lasso_lambda_min",
    "casual_total_share",
    "registered_total_share"
  ),
  value = c(
    nrow(bike_hour),
    ncol(bike_hour_raw),
    nrow(bike_day),
    round(mean(bike_hour$cnt), 3),
    round(median(bike_hour$cnt), 3),
    max(bike_hour$cnt),
    round(mean(bike_hour$casual), 3),
    round(mean(bike_hour$registered), 3),
    group_means |> filter(group_variable == "season") |> arrange(mean_cnt) |> slice(1) |> pull(group),
    group_means |> filter(group_variable == "season") |> arrange(desc(mean_cnt)) |> slice(1) |> pull(group),
    group_means |> filter(group_variable == "weathersit") |> arrange(desc(mean_cnt)) |> slice(1) |> pull(group),
    group_means |> filter(group_variable == "weathersit") |> arrange(mean_cnt) |> slice(1) |> pull(group),
    round(year_summary$mean_cnt[year_summary$yr == "2011年"], 3),
    round(year_summary$mean_cnt[year_summary$yr == "2012年"], 3),
    hour_summary |> arrange(desc(mean_cnt)) |> slice(1) |> pull(hour_num),
    round(hour_summary |> arrange(desc(mean_cnt)) |> slice(1) |> pull(mean_cnt), 3),
    hour_summary |> arrange(mean_cnt) |> slice(1) |> pull(hour_num),
    round(hour_summary |> arrange(mean_cnt) |> slice(1) |> pull(mean_cnt), 3),
    round(working_summary$mean_cnt[working_summary$workingday == "工作日"], 3),
    round(working_summary$mean_cnt[working_summary$workingday == "非工作日"], 3),
    round(overdispersion_ratio, 3),
    round(AIC(pois_model), 3),
    round(AIC(nb_model), 3),
    best_model$model,
    round(best_model$RMSE, 3),
    round(best_model$MAE, 3),
    round(best_model$R_squared, 3),
    top_tree_vars,
    top_rf_vars,
    lasso_nonzero_n,
    round(lasso_meta$lambda_min[1], 6),
    round(user_share_summary$casual_share, 4),
    round(user_share_summary$registered_share, 4)
  )
)
write_table(result_summary, "table99_result_summary.csv")

cat("\nKey result summary\n")
print(result_summary, n = Inf)

sink(file.path(output_dir, "sessionInfo.txt"))
sessionInfo()
sink()

sink()
