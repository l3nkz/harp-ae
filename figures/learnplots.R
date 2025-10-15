library(ggplot2)
library(tidyr)
library(dplyr)
library(gridExtra)
library(patchwork)
library(scales)
library(ggpattern)
library(stringr)
library(purrr)
library(ggfun)
library(tikzDevice)

# Check for proper arguments
if (length(commandArgs(trailingOnly=TRUE)) != 2) {
    cat("Usage: Rscript script_name.R learn.csv ref.csv\n")
    quit(save="no", status=1)
}

custom_theme <- theme_light() + theme(
  text = element_text(size = 14),
  plot.title = element_text(size = 16),
  axis.title = element_text(size = 14), # 14, 11 
  axis.text = element_text(size = 11), # 9
  # legend.background = element_roundrect(fill = "white", color = "black", r = unit(4, "pt")),
  legend.background = element_blank(),
  legend.box = "horizontal",
  legend.box.background = element_roundrect(fill = "white", color = "black", r = unit(4, "pt")),
  legend.title = element_text(size = 12, face="bold", hjust = 0.5), # 14
  legend.title.position = "top",
  legend.text = element_text(size = 12), #12
  legend.key.spacing.x = grid::unit(1, "cm"),
  legend.position = "top",
  legend.spacing = grid::unit(2, "cm"),
  strip.text = element_text(size = 10)
)


# For the PDF
width = 15
height = 11

ymin_single <- 0.3
ymax_single <- 4.5
desired_breaks_single <- c(0.3, 0.6, 1, 2, 4)

ymin_multi <- 0.5
ymax_multi <- 3.5
desired_breaks_multi <- c(0.5, 0.7, 1, 1.5, 2, 3)

ymin_all <- 0.3
ymax_all <- 4.5
desired_breaks_all <-c(0.3, 0.6, 1, 2, 4)

# show wider rows
options(width = 180)

# Load the combined CSV file
csv_path_learn <- commandArgs(trailingOnly=TRUE)[1]
csv_path_ref <- commandArgs(trailingOnly=TRUE)[2]
plot_name <- "plot_learn_middleware25.pdf"

data <- read.csv(csv_path_learn)
df_ref = read.csv(csv_path_ref)

scenarios = unique(data$scenario)

df_ref <- df_ref[df_ref$scenario %in% scenarios, ]
df_cfs <- df_ref %>%
  filter(scheduler == "cfs")
df_cfs_mean <- df_cfs %>%
  group_by(scheduler, scenario, num_apps) %>%
  summarise(
    time_ms_mean = mean(time_ms),
    energy_uj_mean = mean(energy_uj),
    .groups = 'drop'  # This option removes the grouping structure afterwards
  )
df_tetris <- df_ref %>%
  filter(scheduler == "tetris")
df_tetris_mean <- df_tetris %>%
  group_by(scheduler, scenario, num_apps) %>%
  summarise(
    time_ms_mean = mean(time_ms),
    energy_uj_mean = mean(energy_uj),
    .groups = 'drop'  # This option removes the grouping structure afterwards
  )


# Create a sorting column
data$sort_order <- with(data, paste0(sprintf('%05d', num_apps), scenario))

# Convert the scenario column to a factor, ordered by our sorting column
data$scenario <- factor(data$scenario, levels=unique(data$scenario[order(data$sort_order)]))
# print(data)

df_mature <- data %>%
  # Add a new column which splits the 'stages' field
  mutate(stages_split = str_split(stages, "_")) %>%
  # Check if all elements in mature_stages are 'Mature'
  rowwise() %>%
  mutate(all_mature = all(map_lgl(stages_split, ~ .x == "Mature"))) %>%
  ungroup() %>%
  # Group by scenario and find the first run where all stages are mature
  group_by(scenario, num_apps) %>%
  summarize(
    mature_run = if_else(any(all_mature), min(as.integer(run[all_mature])), as.integer(NA)),
    .groups = 'drop'
  )

# Print results
#print(df_mature, n=50)

df_cfs_prepared <- df_cfs_mean %>%
  mutate(run = scheduler) %>%
  select(scenario, num_apps, run, time_ms = time_ms_mean, energy_uj = energy_uj_mean)
df_tetris_prepared <- df_tetris_mean %>%
  mutate(run = scheduler) %>%
  select(scenario, num_apps, run, time_ms = time_ms_mean, energy_uj = energy_uj_mean)

#print(df_ref_prepared)

data$run <- as.character(data$run)
data <- bind_rows(data, df_cfs_prepared)
data <- bind_rows(data, df_tetris_prepared)

# Create a sorting column
data$sort_order <- with(data, paste0(sprintf('%05d', num_apps), scenario))

# Convert the scenario column to a factor, ordered by our sorting column
data$scenario <- factor(data$scenario, levels=unique(data$scenario[order(data$sort_order)]))


baseline <- data %>%
  filter(run == "cfs") %>%
  select(scenario, num_apps, cfs_time_ms = time_ms, cfs_energy_uj = energy_uj)

# print(baseline)

# Join the baseline data with the original dataset
data <- data %>%
  left_join(baseline, by = c("scenario", "num_apps"))

# print(data)

# Calculate improvement metrics
data_impr <- data %>%
  mutate(
    time_improvement = cfs_time_ms / time_ms,
    energy_improvement = cfs_energy_uj / energy_uj
  ) %>%
  # Optionally filter out the baseline cfs rows if they are no longer needed
  filter(run != "cfs")

# print(data_impr)

# Filter out the reference tetris run again
data_impr_runs <- data_impr %>%
  filter(run != "tetris")

data_impr_runs$run <- as.numeric(as.character(data_impr_runs$run))


data_impr_tetris <- data_impr %>%
  filter(run == "tetris")

# Convert 'run' to a factor for proper ordering in the plot if it's not already
# data_impr$run <- as.factor(data_impr$run)

#write.csv(data_impr_runs, "learn_temp_runs.csv")
#write.csv(data_impr_final, "learn_temp_tetris.csv")
#write.csv(df_mature, "learn_temp_mature.csv")

# Define a function to create individual plots
create_subplot <- function(data, data_tetris, data_mature, ymin, ymax, desired_breaks) {
  plot <- ggplot(data) +
    # Time Improvement Plot
    geom_line(aes(x=run, y = time_improvement, color = "Makespan"), linewidth = 0.8) +
    geom_point(aes(x=run, y = time_improvement, color = "Makespan"), size = 2) +
    # Energy Improvement Plot
    geom_line(aes(x=run, y = energy_improvement, color = "Energy"), linewidth = 0.8) +
    geom_point(aes(x=run, y = energy_improvement, color = "Energy"), size = 2) +
    # Adding horizontal lines for 'tetris_balanced' approach
    # geom_hline(data = data_tetris,
    #            aes(yintercept = time_improvement, color = "Time (Final)"), linetype = "dashed",
    #            linewidth = .8) +
    # geom_hline(data = data_tetris,
    #            aes(yintercept = energy_improvement, color = "Energy (Final)"), linetype = "dashed",
    #            linewidth = .8) +
    geom_hline(aes(yintercept = 1), color = "black", linetype = "11", linewidth = .6, lineend="round") +
    # Add shading
    geom_rect(data = data_mature, aes(xmin = -Inf, xmax = coalesce(mature_run-2.5, Inf),
                                    ymin = 0, ymax = Inf, fill = "Training"), alpha = 0.3) +
    geom_rect(data = data_mature %>% filter(!is.na(mature_run)), aes(xmin = mature_run-2.5, xmax = Inf,
                                                                   ymin = 0, ymax = Inf, fill = "Stable"), alpha = 0.3) +
    # Additional plot settings
    scale_x_continuous(breaks = sort(unique(data$run)),  # Set breaks at unique sorted run numbers
                       labels = function(x) ifelse(x %% 2 == 0, x, "")) +  # Convert numbers to character for integer labels
    scale_color_manual(values = c("Makespan" = "deepskyblue3",
                                  "Energy" = "seagreen3"),
                                  #"Time (Final)" = "blue",
                                  #"Energy (Final)" = "green"),
                                  #"Baseline" = "black"),
                       breaks = c("Makespan", "Energy")) + #, "Time (Final)", "Energy (Final)")) + #, "Baseline")) +
    scale_fill_manual(values = c("Training" = "#88B8BE", "Stable" = "#326EA0"),
                      breaks = c("Training", "Stable")) +
    guides(
      color = guide_legend(
        title = "Metric", 
        override.aes = list(
          linetype = c("solid", "solid"), # "dashed", "dashed"), #, "dashed"),
          shape = c(16, 16) # , NA, NA) #, NA)  # Only show points for Time and Energy
        )
      ), 
      fill = guide_legend(title = "Learning Stages")
    ) +
    scale_y_log10(breaks = desired_breaks, labels = function(y) ifelse(y == 1, "CFS", y)) +
    labs(y = "Improvement Factor", x = "Learning Time (s)") +
    custom_theme +
    facet_wrap(~scenario, ncol=5) + 
    # facet_wrap(~scenario, ncol=3, scales = "free_y") + 
    coord_cartesian(ylim = c(ymin, ymax))

  return(plot)
}


print(df_mature)

p_all <- create_subplot(data_impr_runs, data_impr_tetris, df_mature, ymin_all, ymax_all, desired_breaks_all)

# Save to PDF
ggsave(file = plot_name, plot = p_all, width = width, height = height)

