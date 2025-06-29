# =========================================================================
# SCRIPT: New Tables Integration
# VERSION: 6.0 (Final, Corrected, and Robust)
#
# PURPOSE:
#   A standalone script that correctly implements the user's blueprint. It
#   uses the proven `get_sidra(api=...)` method to ensure all fetches
#   succeed and includes complete, robust processing logic for all modules.
# =========================================================================

# --- 0. Setup ---
suppressPackageStartupMessages({
  library(sidrar)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(zoo)
})

# --- 1. Constants ---
MACEIO_CODE <- "2704302"
YEAR_RANGE_INTEGRATION <- 2000:2022
RACE_CODES_MAP <- c("Branca"="Wht", "Preta"="Blk", "Amarela"="Ylw", "Parda"="Brn", "Indígena"="Ind", "Sem declaração"="Ign", "Total"="T")
SEX_CODES_MAP  <- c("Homens"="M", "Mulheres"="W", "Total"="T", "Ignorado"="U")

# --- 2. Definitive Master Configuration ---
TABLE_INTEGRATION_CONFIG <- list(
  # Module 1: Household Anchors
  hh_2000 = list(id="2009", p="2000", d="M1-HH-2000", v="96", c=list(`Situação do domicílio`="Total", `Número de dormitórios`="Total")),
  hh_2010 = list(id="2009", p="2010", d="M1-HH-2010", v="96", c=list(`Situação do domicílio`="Total", `Número de dormitórios`="Total")),
  hh_2022 = list(id="4712", p="2022", d="M1-HH-2022", v="381", c=list()),
  
  # Module 2: Infrastructure
  infra_2000 = list(id="1453", p="2000", d="M2-Infra-2000", v="96", c=list(`Tipo de esgotamento sanitário`="all", `Forma de abastecimento de água`="Total")),
  infra_2010 = list(id="3218", p="2010", d="M2-Infra-2010", v="96", c=list(`Existência de banheiro ou sanitário e esgotamento sanitário`="all", `Destino do lixo`="all", `Existência de energia elétrica`="all", `Forma de abastecimento de água`="Total")),
  infra_2022 = list(id="6805", p="2022", d="M2-Infra-2022", v="381", c=list(`Tipo de esgotamento sanitário`="all")),
  
  # Module 3: Education
  edu_lit_2010 = list(id="1383", p="2010", d="M3-Literacy-2010", v="1646", c=list(`Sexo`="all")),
  edu_attend = list(id="1972", p="2000,2010", d="M3-Attendance-2000/10", v="690", c=list(`Nível de ensino ou curso que frequentavam`="all", `Rede de ensino`="Total")),
  
  # Module 4 & 5: Social & Vital
  social_labor = list(id="2098", p="2000,2010", d="M4-Labor-2000/10", v="140", c=list(`Cor ou raça`="all", `Condição de atividade na semana de referência`="all", `Grupo de idade`="all")),
  vital_deaths = list(id="2654", p=paste(2003:2022, collapse=","), d="M5-Deaths", v="343", c=list(`Natureza do óbito`="all", `Sexo`="all", `Local de ocorrência`="all", `Mês de ocorrência`="Total", `Idade do(a) falecido(a)`="all"))
)


# --- 3. The Correct and Robust Fetching Engine ---
fetch_data <- function(config, geo_code) {
  cat(paste("\n---\nFetching:", config$d, "(Table:", config$id, ")\n"))
  
  metadata <- tryCatch(info_sidra(config$id, wb = FALSE), error = function(e) {
    message(paste("METADATA FAILED:", e$message)); return(NULL)
  })
  if(is.null(metadata)) return(NULL)
  
  years <- str_split_1(config$p, ",")
  
  map_dfr(years, function(year) {
    cat(paste("  -> Fetching year:", year, "..."))
    
    # Build API path string - THIS IS THE ROBUST METHOD
    path_classific <- if (length(config$c) > 0) {
      map_chr(names(config$c), function(class_name_human) {
        
        # Find the real classification code (e.g., 'c11558') from the human-readable name
        class_code <- names(metadata$classific)[map_lgl(metadata$classific, ~ .x == class_name_human)]
        if (length(class_code) == 0) { message(paste(" Classific '", class_name_human, "' not found!")); return("") }
        
        # Get category selection
        cats_selected <- config$c[[class_name_human]]
        
        # Get available categories from metadata
        avail_cats <- metadata$classific_category[[paste(class_code, class_name_human)]]
        
        # Resolve category names to codes
        if (identical(cats_selected, "all")) {
          cat_codes <- avail_cats$cod
        } else {
          cat_codes <- avail_cats$cod[avail_cats$cat %in% cats_selected]
        }
        
        return(paste0("/", class_code, "/allxt/", paste(cat_codes, collapse=",")))
      }) %>% paste(collapse="")
    } else { "" }
    
    api_path <- paste0("/t/", config$id, "/n6/", geo_code, "/p/", year, "/v/", config$v, path_classific)
    
    df_year <- tryCatch(get_sidra(api = api_path), error = function(e) { message(paste(" API FAILED:", e$message)); NULL })
    
    if (is.null(df_year) || nrow(df_year) == 0) cat(" NO DATA\n") else cat(paste0(" SUCCESS (", nrow(df_year), " rows)\n"))
    return(df_year)
  }, .progress = TRUE)
}


# --- 4. Fortified Modular Processing Functions ---

process_household_anchor <- function(d) {
  message("  -> Processing: Household Anchor")
  # Robustly handle cases where one fetch might fail
  df_list <- list(d$hh_2000, d$hh_2010, d$hh_2022)
  if (all(map_lgl(df_list, is.null))) return(NULL)
  
  bind_rows(df_list) %>%
    transmute(ano = as.integer(Ano), hh_total_raw = as.numeric(Valor))
}

process_infrastructure <- function(d) {
  message("  -> Processing: Infrastructure")
  if (is.null(d$infra_2000) && is.null(d$infra_2010) && is.null(d$infra_2022)) return(NULL)
  
  # Process each year safely
  df_2000 <- if(!is.null(d$infra_2000)) d$infra_2000 %>% transmute(ano = 2000, category = `Tipo de esgotamento sanitário`, value = as.numeric(Valor)) else NULL
  df_2010 <- if(!is.null(d$infra_2010)) d$infra_2010 %>% pivot_longer(cols = -c(1:5), names_to = "classification", values_to = "category") %>% transmute(ano = 2010, category = category, value = as.numeric(Valor)) else NULL
  df_2022 <- if(!is.null(d$infra_2022)) d$infra_2022 %>% transmute(ano = 2022, category = `Tipo de esgotamento sanitário`, value = as.numeric(Valor)) else NULL
  
  bind_rows(df_2000, df_2010, df_2022) %>%
    mutate(
      var_name = case_when(
        grepl("Rede geral|rede geral", category) ~ "hh_sanitation_rede_geral",
        grepl("Fossa séptica", category) ~ "hh_sanitation_fossa_septica",
        grepl("Fossa rudimentar", category) ~ "hh_sanitation_fossa_rudimentar",
        grepl("Não tinham banheiro", category) ~ "hh_sanitation_sem_banheiro",
        grepl("Coletado", category) ~ "hh_waste_coletado",
        grepl("^Tinham$", category) ~ "hh_electricity_present",
        grepl("Não tinham", category) ~ "hh_electricity_absent",
        category == "Total" ~ "raw_total", TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(var_name), !is.na(value)) %>%
    group_by(ano, var_name) %>%
    summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = var_name, values_from = value, values_fill = 0)
}

process_education <- function(d) {
  message("  -> Processing: Education")
  if (is.null(d$edu_lit_2010) && is.null(d$edu_attend)) return(NULL)
  
  lit_2010 <- if(!is.null(d$edu_lit_2010)) d$edu_lit_2010 %>% transmute(ano=2010, var_name=paste0("rate_lit_10p_", recode(Sexo, !!!SEX_CODES_MAP)), value=as.numeric(Valor)) else NULL
  
  attend <- if(!is.null(d$edu_attend)) d$edu_attend %>%
    mutate(
      level_h = str_to_lower(str_extract(`Nível de ensino ou curso que frequentavam`, "\\w+")),
      var_name = paste0("count_attend_", level_h)
    ) %>%
    transmute(ano = as.integer(Ano), var_name = if_else(level_h=="total", "count_attend_total", var_name), value=as.numeric(Valor))
  else NULL
  
  bind_rows(lit_2010, attend) %>%
    group_by(ano, var_name) %>% summarise(value=sum(value, na.rm=T), .groups="drop") %>%
    pivot_wider(names_from = var_name, values_from = value, values_fill = 0)
}

process_social_vital <- function(d) {
  message("  -> Processing: Social & Vital Statistics")
  if (is.null(d$social_labor) && is.null(d$vital_deaths)) return(NULL)
  
  labor <- if(!is.null(d$social_labor)) d$social_labor %>%
    transmute(
      ano = as.integer(Ano),
      race_h = recode(`Cor ou raça`, !!!RACE_CODES_MAP),
      activity_h = recode(`Condição de atividade na semana de referência`, "Total"="T", "Economicamente ativas"="Active", "Não economicamente ativas"="Inactive"),
      age_h = recode(`Grupo de idade`, "Total"="T", "10 a 14 anos"="10_14", "15 a 19 anos"="15_19", "20 a 24 anos"="20_24", "25 a 29 anos"="25_29", "30 a 39 anos"="30_39", "40 a 49 anos"="40_49", "50 a 59 anos"="50_59", "60 a 69 anos"="60_69", "70 anos ou mais"="70p"),
      value = as.numeric(Valor)
    ) %>%
    pivot_wider(names_from = c(race_h, activity_h, age_h), names_prefix = "pop_labor_", names_sep = "_", values_from = value, values_fill = 0)
  else NULL
  
  deaths <- if(!is.null(d$vital_deaths)) d$vital_deaths %>%
    group_by(ano=as.integer(Ano), nature_h = `Natureza do óbito`, sex_h = Sexo, loc_h = `Local de ocorrência`, age_h = `Idade do(a) falecido(a)`) %>%
    summarise(value = sum(as.numeric(Valor), na.rm=T), .groups="drop") %>%
    pivot_wider(names_from=c(nature_h, sex_h, loc_h, age_h), names_prefix="deaths_", names_sep="_", values_from=value, values_fill=0)
  else NULL
  
  if(is.null(labor)) return(deaths)
  if(is.null(deaths)) return(labor)
  full_join(labor, deaths, by="ano")
}

# --- 5. Main Orchestrator Function ---
create_new_integrated_dataset <- function(geo_code, year_span, config_list) {
  message(paste0("\n>>> STARTING INTEGRATION FOR GEO: ", geo_code, ", YEARS: ", min(year_span), "-", max(year_span), " <<<\n"))
  
  raw_data <- map(config_list, ~fetch_data(.x, geo_code = geo_code))
  
  message("\n\n>>> PROCESSING FETCHED DATA INTO INDIVIDUAL DATAFRAMES <<<\n")
  processed_dfs <- list()
  processed_dfs$households <- process_household_anchor(raw_data)
  processed_dfs$infrastructure <- process_infrastructure(raw_data)
  processed_dfs$education <- process_education(raw_data)
  processed_dfs$social_vital <- process_social_vital(raw_data)
  
  processed_dfs <- compact(processed_dfs)
  if (length(processed_dfs) == 0) { message("FATAL: No data could be processed."); return(NULL) }
  
  message("\n\n>>> JOINING PROCESSED DATAFRAMES INTO FINAL DATASET <<<\n")
  base_grid <- tibble(ano = as.integer(year_span))
  
  integrated_data <- reduce(processed_dfs, ~ full_join(.x, .y, by = "ano")) %>%
    mutate(muni_code = geo_code, .before=1) %>%
    mutate(across(where(is.numeric) & !c(ano), ~replace_na(., 0))) %>%
    arrange(muni_code, ano)
  
  message("\n>>> INTEGRATION COMPLETE! <<<\n")
  return(list(integrated_data = integrated_data, individual_dfs = processed_dfs, raw_data = raw_data))
}

# --- 6. Execute the Test ---
integration_results <- create_new_integrated_dataset(
  geo_code = MACEIO_CODE,
  year_span = YEAR_RANGE_INTEGRATION,
  config_list = TABLE_INTEGRATION_CONFIG
)

# --- 7. Inspect the Output ---
if (!is.null(integration_results)) {
  message("\n\n=========================================================\n--- INSPECTING INDIVIDUAL PROCESSED DATAFRAMES ---\n=========================================================\n")
  walk(names(integration_results$individual_dfs), ~{
    cat(paste("\n--- Dataframe:", .x, "---\n"))
    print(glimpse(integration_results$individual_dfs[[.x]]))
  })
  
  message("\n\n=========================================================\n--- INSPECTING THE FINAL INTEGRATED DATAFRAME ---\n=========================================================\n")
  message("Final Dataset Dimensions: ", paste(dim(integration_results$integrated_data), collapse=" x "), "\n")
  glimpse(integration_results$integrated_data)
}