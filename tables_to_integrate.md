

### **The Final Engineering Blueprint: `demographic_basis.R V2.0`**

#### **Preamble: Core Architectural Principles**

1.  **Modular Design:** The pipeline will be refactored. Instead of one monolithic function, we will create theme-specific processing functions (e.g., `process_household_infrastructure`, `process_education_variables`). The main `create_demographic_basis_pipeline` function will orchestrate these modules.
2.  **Harmonization First:** For each module, the first step will be to define and apply a harmonization map for categories (especially for sanitation and education) and a dedicated helper function for age-band mapping (`map_age_to_target_bands`). This ensures consistency before any calculations are performed.
3.  **Anchor-Share-Interpolate-Reconstitute:** This remains our core philosophy for all census-based variables. The appropriate anchor (`pop_total_est` or `hh_total_est`) will be used for each module.
4.  **Flow Data Processing:** Annual data (vital statistics) will be handled by a separate processor that focuses on fetching and reshaping granular combinations, not interpolation.
5.  **Timeframe:** All interpolated data will be generated for the **2010-2022** period, ensuring the highest data quality and consistency. The framework will be built to accommodate 2000-era data in the future if desired.

---

### **Module 1: Foundational Anchors Processor**

*   **Objective:** To create the two fundamental annual anchor variables: `pop_total_est` (existing) and the new `hh_total_est`.
*   **Source Tables & Variables:**
    *   **Households (2010):** Table `2009`, Variable `96` ("Domicílios particulares permanentes"), filtered by `c1 = Situação do domicílio == Total`.
    *   **Households (2022):** Table `4712`, Variable `381` ("Domicílios particulares permanentes ocupados").
*   **Harmonization Strategy:**
    *   The variable names ("...permanentes" vs. "...permanentes ocupados") are functionally identical for the purpose of creating a total household anchor. No complex harmonization is needed.
*   **Data Processing & Integration Logic:**
    1.  The existing logic for creating `pop_total_est` remains unchanged.
    2.  A new block will be added to the pipeline.
    3.  It will fetch the total household count for each municipality from Table `2009` for the year 2010.
    4.  It will fetch the total household count for each municipality from Table `4712` for the year 2022.
    5.  It will create a complete `muni_code` x `ano` grid for 2010-2022.
    6.  It will use `zoo::na.approx()` on the two data points (2010, 2022) to perform a linear interpolation, creating a continuous decimal series for `hh_total_est`.
    7.  The final `hh_total_est` will be produced by applying `round()` to the decimal series, ensuring an integer result.
*   **Proposed Output Columns:** `hh_total_est`.

---

### **Module 2: Household Richness - Infrastructure Processor**

*   **Objective:** To create annual, granular time series for household sanitation, waste disposal, and electricity access.
*   **Source Tables & Classifications:**
    *   **2022 Data:** Table `6805`, `c11558 = Tipo de esgotamento sanitário`.
    *   **2010 Data:** Table `3218`, using `c299 = Existência de banheiro...`, `c67 = Destino do lixo`, `c309 = Existência de energia elétrica`.
*   **Harmonization Strategy:**
    *   **This is the most critical step.** We will use the 2022 schema from Table `6805` as our target for sanitation. A new helper function, `harmonize_sanitation_categories()`, will be created.
    *   **Harmonization Map (`3218` -> `6805`):**
        *   `c299: "Tinham banheiro... - rede geral de esgoto ou pluvial ou fossa séptica"` -> This is a composite category. We must decide whether to map it to `c11558: "Rede geral ou pluvial"` or to split its value proportionally. For robustness, the initial implementation will map it directly to `c11558: "Rede geral, rede pluvial ou fossa ligada à rede"`.
        *   `c299: "Tinham banheiro... - outro"` -> Maps to `c11558: "Fossa rudimentar ou buraco"` or `"Outra forma"`. We'll default to "Outra forma".
        *   `c299: "Não tinham banheiro nem sanitário"` -> Maps directly to `c11558: "Não tinham banheiro nem sanitário"`.
    *   **Waste & Electricity:** These variables exist only in 2010. They will be treated as snapshots for now.
*   **Data Processing & Integration Logic:**
    1.  Fetch the raw data from Tables `3218` and `6805`.
    2.  Apply the `harmonize_sanitation_categories()` mapping to the 2010 data to align it with the 2022 schema.
    3.  For each harmonized sanitation category (e.g., `Rede_Geral`, `Fossa_Septica`), calculate its share of total households (`value / hh_total_est`) for 2010 and 2022.
    4.  Use a 2-point linear interpolation (`zoo::na.approx`) on these shares for the 2010-2022 period.
    5.  Reconstitute the final integer counts by multiplying the interpolated share by the annual `hh_total_est`.
    6.  For waste and electricity, calculate the 2010 share and apply it to the `hh_total_est` for all years as a provisional estimate (`_est_prov`).
*   **Proposed Output Columns:** `hh_sanitation_rede_geral_est`, `hh_sanitation_fossa_septica_est`, `hh_waste_collected_est_prov`, `hh_electricity_est_prov`.

---

### **Module 3: Person-Based Richness - Education Processor**

*   **Objective:** To integrate granular, multi-dimensional data on population literacy and school attendance.
*   **Source Tables & Classifications:**
    *   **Literacy:** `1383` (2010), `9543` (2022). We will use `2987` (2000) for historical context but focus interpolation on 2010-2022.
    *   **Attendance:** `1972` (2000, 2010).
*   **Harmonization Strategy:**
    *   **Literacy:** The key challenge is the age base (`10+` vs. `15+`). We will create a methodologically honest series for **`pop_literacy_rate_15p`**. We will need to re-fetch the 2010 data from a more granular table (like `2093`) to get the `15+` population base for that year to calculate a comparable rate. The 2022 data from `9543` is perfect as is.
    *   **Age Bands:** A `map_age_to_target_bands()` function will be created to map the detailed age groups in `9543` (`c287`) to our `TARGET_AGE_BANDS`.
    *   **Attendance Categories:** The `c11798` classification will be harmonized into fewer, more robust categories: `Creche`, `Pre-escola`, `Fundamental` (combining regular and EJA), `Medio` (combining regular, EJA, pre-vestibular), `Superior` (combining graduação, mestrado, doutorado).
*   **Data Processing & Integration Logic:**
    1.  **Literacy:**
        *   Fetch the granular literacy rates from `9543` (2022) for every combination of `c2` (Sex), `c86` (Race), and `c287` (Age).
        *   Fetch the corresponding granular data for 2010.
        *   Directly interpolate these granular rates between 2010 and 2022.
        *   Create final count variables by multiplying the interpolated rate by the corresponding interpolated granular population group (e.g., `pop_M_Wht_20-24`).
    2.  **Attendance:**
        *   For each harmonized attendance category, calculate its share of the total population for 2010 from Table `1972`.
        *   Apply this 2010 share to the annual `pop_total_est` to generate provisional estimates post-2010, until the 2022 data is found.
*   **Proposed Output Columns:** `pop_literacy_rate_est_F_Parda_30-39`, `pop_literate_est_F_Parda_30-39`, `pop_attendance_superior_share_est_prov`.

---

### **Module 4 & 5: Social & Vital Statistics (Flow Processor)**

*   **Objective:** To process all annual "flow" data, requiring no interpolation, only granular fetching and reshaping.
*   **Source Tables & Classifications:**
    *   **Births:** `2609` (using `c240`=Mother's Age, `c2`=Sex)
    *   **Deaths:** `2654` (using `c1836`=Cause, `c2`=Sex, `c260`=Age, `c257`=Location)
    *   **Marriages:** `4412` (using `c666`/`c667`=Spouse Age)
    *   **Divorces:** `1695` (using `c274`/`c275`=Spouse Age)
    *   **Marital Status (Snapshot):** `1539` (using `c464`) from 2010.
    *   **Labor Force (Snapshot):** `2098` (using `c12056`, `c86`, `c58`) from 2010.
*   **Harmonization Strategy:**
    *   **THE CORE TASK:** A new, robust `map_age_to_target_bands(source_classification, source_table_id)` function is required. This function will contain the explicit logic to map the highly detailed age categories from `c260` (Deaths), `c240` (Births), etc., to our `TARGET_AGE_BANDS`. This is the most complex piece of harmonization required.
        *   *Example:* `c260: "Menos de 1 ano", "1 ano", "2 anos", "3 anos", "4 anos"` will all map to `TARGET_AGE_BANDS: "00_04"`.
*   **Data Processing & Integration Logic:**
    1.  This module will **not** interpolate. It will be a `process_annual_flows` function.
    2.  It will define a list of target variables, where each variable is a specific combination of classifications (e.g., `deaths_F_Natural_age_40-49`).
    3.  The function will loop through this list. In each loop, it will make a targeted `get_sidra` call with the appropriate `category = list(...)` argument to fetch that specific data point for all years (2010-2022).
    4.  The results will be joined to the main data frame, creating a rich set of annual variables.
    5.  For the 2010 snapshot data (Marital/Labor), the 2010 shares will be calculated and applied to the annual `pop_total_est` for provisional estimates, as described in the previous plan.
*   **Proposed Output Columns:** `births_M_mother_age_20-24`, `deaths_F_Natural_age_40-49`, `deaths_M_NonNatural_age_20-24`, `deaths_total_hospital`, `marriages_total`, `divorces_total`, `pop_labor_force_active_share_est_prov`.




#####################################################################

MODULE: Module 1: Foundational Anchors

#####################################################################

=====================================================
INFO FOR SIDRA TABLE: 2009

$table
[1] "Tabela 2009: Domicílios particulares permanentes e Moradores em Domicílios particulares permanentes por situação do domicílio e número de dormitórios"

$period
[1] "2000, 2010"

$variable
cod                                                                             desc
1      96                                   Domicílios particulares permanentes (Unidades)
2 1000096              Domicílios particulares permanentes - percentual do total geral (%)
3     137                       Moradores em domicílios particulares permanentes (Pessoas)
4 1000137 Moradores em domicílios particulares permanentes - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c1 = Situação do domicílio (3):
cod   desc
1   0  Total
2   1 Urbana
3   2  Rural

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c74 = Número de dormitórios (7):
cod                  desc
1     0                 Total
2  3361          1 dormitório
3  3362         2 dormitórios
4  3363         3 dormitórios
5  3364         4 dormitórios
6  3365         5 dormitórios
7 95775 6 dormitórios ou mais

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
3             IRD Região Integrada de Desenvolvimento até 2020 (3)
4         UrbAglo                       Aglomeração Urbana  [2010]
5          Region                                Grande Região (5)
6           State                        Unidade da Federação (27)
7            City                                Município (5.565)
8     MetroRegion               Região Metropolitana até 2020 (36)
9      MesoRegion                     Mesorregião Geográfica (137)
10    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 4712

$table
[1] "Tabela 4712: Domicílios particulares permanentes ocupados, Moradores em domicílios particulares permanentes ocupados e Média de moradores em domicílios particulares permanentes ocupados"

$period
[1] "2022"

$variable
cod                                                                         desc
1  381                    Domicílios particulares permanentes ocupados (Domicílios)
2  382          Moradores em domicílios particulares permanentes ocupados (Pessoas)
3 5930 Média de moradores em domicílios particulares permanentes ocupados (Pessoas)

$classific_category
NULL

$geo
cod                      desc
1 Brazil                Brasil (1)
2 Region         Grande Região (5)
3  State Unidade da Federação (27)
4   City         Município (5.570)

#####################################################################

MODULE: Module 2: Household Richness - Infrastructure

#####################################################################

=====================================================
INFO FOR SIDRA TABLE: 1453

$table
[1] "Tabela 1453: Domicílios particulares permanentes por tipo de esgotamento sanitário e abastecimento de água"

$period
[1] "2000"

$variable
cod                                                                desc
1      96                      Domicílios particulares permanentes (Unidades)
2 1000096 Domicílios particulares permanentes - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c11558 = Tipo de esgotamento sanitário (8):
cod                              desc
1     0                             Total
2 92855   Rede geral de esgoto ou pluvial
3 92856                     Fossa séptica
4 92857                  Fossa rudimentar
5 92858                              Vala
6 92859                  Rio, lago ou mar
7 92860                  Outro escoadouro
8 92861 Não tinham banheiro nem sanitário

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c61 = Forma de abastecimento de água (12):
cod                                                                        desc
1      0                                                                       Total
2  92853                                                                  Rede geral
3  92847                             Rede geral - canalizada em pelo menos um cômodo
4  92848                        Rede geral - canalizada só na propriedade ou terreno
5  92854                                           Poço ou nascente (na propriedade)
6  92849      Poço ou nascente (na propriedade) - canalizada em pelo menos um cômodo
7  92850 Poço ou nascente (na propriedade) - canalizada só na propriedade ou terreno
8  92851                          Poço ou nascente (na propriedade) - não canalizada
9  92852                                                                 Outra forma
10 92866                            Outra forma - canalizada em pelo menos um cômodo
11 92867                       Outra forma - canalizada só na propriedade ou terreno
12 92868                                                Outra forma - não canalizada

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2        District                                 Distrito (9.749)
3    Neighborhood                                   Bairro (7.268)
4     subdistrict                                Subdistrito (388)
5  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (26)
6             IRD Região Integrada de Desenvolvimento até 2020 (1)
7          Region                                Grande Região (5)
8           State                        Unidade da Federação (27)
9            City                                Município (5.507)
10    MetroRegion               Região Metropolitana até 2020 (22)
11     MesoRegion                     Mesorregião Geográfica (137)
12    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 3218

$table
[1] "Tabela 3218: Domicílios particulares permanentes, por forma de abastecimento de água, segundo a existência de banheiro ou sanitário e esgotamento sanitário, o destino do lixo e a existência de energia elétrica"

$period
[1] "2010"

$variable
cod                                                                desc
1      96                      Domicílios particulares permanentes (Unidades)
2 1000096 Domicílios particulares permanentes - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c61 = Forma de abastecimento de água (8):
cod                                 desc
1      0                                Total
2  92853                           Rede geral
3  10971      Poço ou nascente na propriedade
4 121290 Poço ou nascente fora da propriedade
5 121294          Rio, açude, lago ou igarapé
6 121296           Poço ou nascente na aldeia
7 121297      Poço ou nascente fora da aldeia
8 121295                                Outra

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c299 = Existência de banheiro ou sanitário e esgotamento sanitário (8):
cod
1     0
2  2944
3  9678
4  2950
5  2958
6  9679
7  2964
8 10006
desc
1                                                                                              Total
2                                                    Tinham banheiro - de uso exclusivo do domicílio
3 Tinham banheiro - de uso exclusivo do domicílio - rede geral de esgoto ou pluvial ou fossa séptica
4                                            Tinham banheiro - de uso exclusivo do domicílio - outro
5                                                                                   Tinham sanitário
6                                Tinham sanitário - rede geral de esgoto ou pluvial ou fossa séptica
7                                                                Tinham sanitário - outro escoadouro
8                                                                  Não tinham banheiro nem sanitário

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c67 = Destino do lixo (5):
cod                                      desc
1     0                                     Total
2  2520                                  Coletado
3 92863           Coletado por serviço de limpeza
4 92864 Coletado em caçamba de serviço de limpeza
5  1091                             Outro destino

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c309 = Existência de energia elétrica (3):
cod       desc
1    0      Total
2 3011     Tinham
3 3018 Não tinham

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2        District                                Distrito (10.277)
3    Neighborhood                                  Bairro (14.211)
4     subdistrict                                Subdistrito (658)
5  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
6             IRD Região Integrada de Desenvolvimento até 2020 (3)
7         UrbAglo                           Aglomeração Urbana (2)
8          Region                                Grande Região (5)
9       PopArrang                       Arranjo Populacional (284)
10          State                        Unidade da Federação (27)
11           City                                Município (5.565)
12    MetroRegion               Região Metropolitana até 2020 (36)
13     MesoRegion                     Mesorregião Geográfica (137)
14    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 6805

$table
[1] "Tabela 6805: Domicílios particulares permanentes ocupados, por tipo de esgotamento sanitário"

$period
[1] "2022"

$variable
cod                                                                         desc
1     381                      Domicílios particulares permanentes ocupados (Unidades)
2 1000381 Domicílios particulares permanentes ocupados - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c11558 = Tipo de esgotamento sanitário (10):
cod                                            desc
1  46292                                           Total
2  46290 Rede geral, rede pluvial ou fossa ligada à rede
3  72110                           Rede geral ou pluvial
4  72111     Fossa séptica ou fossa filtro ligada à rede
5  72112 Fossa séptica ou fossa filtro não ligada à rede
6  72113                      Fossa rudimentar ou buraco
7  92858                                            Vala
8  72114                       Rio, lago, córrego ou mar
9  72115                                     Outra forma
10 92861               Não tinham banheiro nem sanitário

$geo
cod                      desc
1 Brazil                Brasil (1)
2 Region         Grande Região (5)
3  State Unidade da Federação (27)
4   City         Município (5.570)

#####################################################################

MODULE: Module 3: Person-Based Richness - Education

#####################################################################

=====================================================
INFO FOR SIDRA TABLE: 2987

$table
[1] "Tabela 2987: Pessoas de 10 anos ou mais de idade, total, alfabetizadas e taxa de alfabetização por grupos de idade"

$period
[1] "2000"

$variable
cod                                                                             desc
1     140                                      Pessoas de  anos ou mais de idade (Pessoas)
2 1000140                Pessoas de  anos ou mais de idade - percentual do total geral (%)
3    1645                       Pessoas de  anos ou mais de idade, alfabetizadas (Pessoas)
4 1001645 Pessoas de  anos ou mais de idade, alfabetizadas - percentual do total geral (%)
5    1646                  Taxa de alfabetização das pessoas de  anos ou mais de idade (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c58 = Grupo de idade (4):
cod            desc
1  95253           Total
2   1142    10 a 14 anos
3   1143    15 a 19 anos
4 109062 20 anos ou mais

$geo
cod                                             desc
1         Brazil                                       Brasil (1)
2 MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (26)
3            IRD Região Integrada de Desenvolvimento até 2020 (1)
4         Region                                Grande Região (5)
5          State                        Unidade da Federação (27)
6           City                                Município (5.507)
7    MetroRegion               Região Metropolitana até 2020 (22)
8     MesoRegion                     Mesorregião Geográfica (137)
9    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 1383

$table
[1] "Tabela 1383: Taxa de alfabetização das pessoas de 10 anos ou mais de idade por sexo"

$period
[1] "2010"

$variable
cod                                                            desc
1 1646 Taxa de alfabetização das pessoas de  anos ou mais de idade (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c2 = Sexo (3):
cod     desc
1 6794    Total
2    4   Homens
3    5 Mulheres

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2        District                                Distrito (10.277)
3    Neighborhood                                  Bairro (14.216)
4     subdistrict                                Subdistrito (658)
5  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
6             IRD Região Integrada de Desenvolvimento até 2020 (3)
7          Region                                Grande Região (5)
8           State                        Unidade da Federação (27)
9            City                                Município (5.565)
10    MetroRegion               Região Metropolitana até 2020 (36)
11     MesoRegion                     Mesorregião Geográfica (137)
12    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 9543

$table
[1] "Tabela 9543: Taxa de alfabetização das pessoas de 15 anos ou mais de idade por sexo, cor ou raça e grupos de idade"

$period
[1] "2022"

$variable
cod                                                            desc
1 2513 Taxa de alfabetização das pessoas de  anos ou mais de idade (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c2 = Sexo (3):
cod     desc
1 6794    Total
2    4   Homens
3    5 Mulheres

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c86 = Cor ou raça (6):
cod     desc
1 95251    Total
2  2776   Branca
3  2777    Preta
4  2778  Amarela
5  2779    Parda
6  2780 Indígena

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c287 = Idade (60):
cod            desc
1  100362           Total
2   93086    15 a 19 anos
3    6572         15 anos
4    6573         16 anos
5    6574         17 anos
6    6575         18 anos
7    6576         19 anos
8   93087    20 a 24 anos
9    6577         20 anos
10   6578         21 anos
11   6579         22 anos
12   6580         23 anos
13   6581         24 anos
14   2999    25 a 34 anos
15   6582         25 anos
16   6656         26 anos
17   6657         27 anos
18   6658         28 anos
19   6659         29 anos
20   6583         30 anos
21   6584         31 anos
22   6585         32 anos
23   6586         33 anos
24   6587         34 anos
25   9482    35 a 44 anos
26   6588         35 anos
27   6589         36 anos
28   6590         37 anos
29   6591         38 anos
30   6592         39 anos
31   6593         40 anos
32   6594         41 anos
33   6595         42 anos
34   6596         43 anos
35   6597         44 anos
36   9483    45 a 54 anos
37   6598         45 anos
38   6599         46 anos
39   6600         47 anos
40   6601         48 anos
41   6602         49 anos
42   6603         50 anos
43   6604         51 anos
44   6605         52 anos
45   6606         53 anos
46   6607         54 anos
47   9484    55 a 64 anos
48   6608         55 anos
49   6609         56 anos
50   6610         57 anos
51   6611         58 anos
52   6612         59 anos
53   6613         60 anos
54   6614         61 anos
55   6615         62 anos
56   6616         63 anos
57   6617         64 anos
58   3000 65 anos ou mais
59   9486 75 anos ou mais
60 113623 80 anos ou mais

$geo
cod                      desc
1 Brazil                Brasil (1)
2 Region         Grande Região (5)
3  State Unidade da Federação (27)
4   City         Município (5.570)

=====================================================
INFO FOR SIDRA TABLE: 1972

$table
[1] "Tabela 1972: Pessoas que frequentavam creche ou escola por nível e rede de ensino"

$period
[1] "2000, 2010"

$variable
cod                                                                      desc
1     690                       Pessoas que frequentavam escola ou creche (Pessoas)
2 1000690 Pessoas que frequentavam escola ou creche - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c11798 = Nível de ensino ou curso que frequentavam (19):
cod                                               desc
1       0                                              Total
2   95301                                             Creche
3   95302             Pré-escolar ou classe de alfabetização
4  107454                                        Pré-escolar
5    7904                            Classe de alfabetização
6    7905                  Alfabetização de jovens e adultos
7   95303                           Alfabetização de adultos
8    7906                      Regular de ensino fundamental
9    7907 Educação de jovens e adultos do ensino fundamental
10  95304                                        Fundamental
11   7908                            Regular do ensino médio
12   7909       Educação de jovens e adultos do ensino médio
13  95305                                              Médio
14  95306                                     Pré-vestibular
15  95307                              Superior de graduação
16   7910                   Especialização de nível superior
17   7911                                           Mestrado
18   7912                                          Doutorado
19  95308                              Mestrado ou doutorado

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c11797 = Rede de ensino (3):
cod       desc
1     0      Total
2 95298    Pública
3 95297 Particular

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
3             IRD Região Integrada de Desenvolvimento até 2020 (3)
4         UrbAglo                       Aglomeração Urbana  [2010]
5          Region                                Grande Região (5)
6           State                        Unidade da Federação (27)
7            City                                Município (5.565)
8     MetroRegion               Região Metropolitana até 2020 (36)
9      MesoRegion                     Mesorregião Geográfica (137)
10    MicroRegion                    Microrregião Geográfica (558)

#####################################################################

MODULE: Module 4: Person-Based Richness - Social & Economic Structure

#####################################################################

=====================================================
INFO FOR SIDRA TABLE: 1539

$table
[1] "Tabela 1539: Pessoas de 10 anos ou mais de idade, por estado conjugal - Resultados Gerais da Amostra"

$period
[1] "2010"

$variable
cod                                                              desc
1     140                       Pessoas de  anos ou mais de idade (Pessoas)
2 1000140 Pessoas de  anos ou mais de idade - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c464 = Estado conjugal (5):
cod                                desc
1     0                               Total
2 12108                     Viviam em união
3 12109                 Não viviam em união
4 12110 Não viviam, mas já viveram em união
5 12111              Nunca viveram em união

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
3             IRD Região Integrada de Desenvolvimento até 2020 (3)
4         UrbAglo                           Aglomeração Urbana (2)
5          Region                                Grande Região (5)
6           State                        Unidade da Federação (27)
7            City                                Município (5.565)
8     MetroRegion               Região Metropolitana até 2020 (36)
9      MesoRegion                     Mesorregião Geográfica (137)
10    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 2098

$table
[1] "Tabela 2098: Pessoas de 10 anos ou mais de idade por cor ou raça, condição de atividade na semana de referência e grupos de idade"

$period
[1] "2000, 2010"

$variable
cod                                                              desc
1     140                       Pessoas de  anos ou mais de idade (Pessoas)
2 1000140 Pessoas de  anos ou mais de idade - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c86 = Cor ou raça (7):
cod           desc
1    0          Total
2 2776         Branca
3 2777          Preta
4 2778        Amarela
5 2779          Parda
6 2780       Indígena
7 2781 Sem declaração

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c12056 = Condição de atividade na semana de referência (3):
cod                      desc
1     0                     Total
2 99566     Economicamente ativas
3 99567 Não economicamente ativas

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c58 = Grupo de idade (22):
cod            desc
1       0           Total
2    1142    10 a 14 anos
3  118282    10 a 13 anos
4    2497         14 anos
5    1143    15 a 19 anos
6    2792    15 a 17 anos
7   92982    18 e 19 anos
8    1144    20 a 24 anos
9    1145    25 a 29 anos
10   3299    30 a 39 anos
11   1146    30 a 34 anos
12   1147    35 a 39 anos
13   3300    40 a 49 anos
14   1148    40 a 44 anos
15   1149    45 a 49 anos
16   3301    50 a 59 anos
17   1150    50 a 54 anos
18   1151    55 a 59 anos
19   3520    60 a 69 anos
20   3244 70 anos ou mais
21  95252    70 a 79 anos
22   2503 80 anos ou mais

$geo
cod                                             desc
1          Brazil                                       Brasil (1)
2  MetroRegionDiv  Região Metropolitana e Subdivisão até 2020 (46)
3             IRD Região Integrada de Desenvolvimento até 2020 (3)
4         UrbAglo                       Aglomeração Urbana  [2010]
5          Region                                Grande Região (5)
6           State                        Unidade da Federação (27)
7            City                                Município (5.565)
8     MetroRegion               Região Metropolitana até 2020 (36)
9      MesoRegion                     Mesorregião Geográfica (137)
10    MicroRegion                    Microrregião Geográfica (558)

#####################################################################

MODULE: Module 5: Annual Vital & Social Statistics (Flow Data)

#####################################################################

=====================================================
INFO FOR SIDRA TABLE: 2609

$table
[1] "Tabela 2609: Nascidos vivos, por ano de nascimento, grupos de idade da mãe na ocasião do parto, sexo e lugar de residência da mãe"

$period
[1] "2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023"

$variable
cod                                                              desc
1     217                       Nascidos vivos registrados no ano (Pessoas)
2 1000217 Nascidos vivos registrados no ano - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c232 = Ano de nascimento (61):
cod           desc
1       0          Total
2   77792           2023
3   71500           2022
4   58297           2021
5   56680           2020
6   48972           2019
7   47550           2018
8   46256           2017
9   40523           2016
10  40289           2015
11  39331           2014
12  33044           2013
13  31660           2012
14  15773           2011
15  12029           2010
16   7996           2009
17 119202           2008
18 118095           2007
19 111751           2006
20 109555           2005
21 107161           2004
22 104320           2003
23 102883           2002
24  98825           2001
25  98824           2000
26  98823           1999
27  94126           1998
28  90891           1997
29  90797           1996
30  90796           1995
31   5198           1994
32   5197           1993
33   5196           1992
34   5195           1991
35   5194           1990
36   5193           1989
37   5192           1988
38   5191           1987
39   5190           1986
40  90781           1985
41  90780           1984
42  90779           1983
43  90778           1982
44  90777           1981
45  90776           1980
46  90775           1979
47  90774           1978
48  90773           1977
49  90772           1976
50  90794           1975
51  90793           1974
52  90792           1973
53  90791           1972
54  90790           1971
55  90789           1970
56  90788           1969
57  90787           1968
58  90786           1967
59  90785           1966
60  90798  Antes de 1966
61 105276 Sem declaração

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c240 = Idade da mãe na ocasião do parto (46):
cod             desc
1     0            Total
2  5370 Menos de 15 anos
3  5414     15 a 19 anos
4  5371          15 anos
5  5372          16 anos
6  5373          17 anos
7  5374          18 anos
8  5375          19 anos
9  5376     20 a 24 anos
10 5377          20 anos
11 5378          21 anos
12 5379          22 anos
13 5380          23 anos
14 5381          24 anos
15 5382     25 a 29 anos
16 5383          25 anos
17 5384          26 anos
18 5385          27 anos
19 5386          28 anos
20 5387          29 anos
21 5388     30 a 34 anos
22 5389          30 anos
23 5390          31 anos
24 5391          32 anos
25 5392          33 anos
26 5393          34 anos
27 5394     35 a 39 anos
28 5395          35 anos
29 5396          36 anos
30 5397          37 anos
31 5398          38 anos
32 5399          39 anos
33 5400     40 a 44 anos
34 5401          40 anos
35 5402          41 anos
36 5403          42 anos
37 5404          43 anos
38 5405          44 anos
39 5406     45 a 49 anos
40 5407          45 anos
41 5408          46 anos
42 5409          47 anos
43 5410          48 anos
44 5411          49 anos
45 5412  50 anos ou mais
46 5413         Ignorada

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c2 = Sexo (4):
cod     desc
1      0    Total
2      4   Homens
3      5 Mulheres
4 104539 Ignorado

$geo
cod                                             desc
1         Brazil                                       Brasil (1)
2 MetroRegionDiv Região Metropolitana e Subdivisão até 2020 (102)
3            IRD Região Integrada de Desenvolvimento até 2020 (3)
4         Region                                Grande Região (5)
5          State                        Unidade da Federação (27)
6           City                                Município (5.570)
7    MetroRegion               Região Metropolitana até 2020 (74)
8     MesoRegion                     Mesorregião Geográfica (137)
9    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 2654

$table
[1] "Tabela 2654: Óbitos, ocorridos no ano, por mês de ocorrência, natureza do óbito, sexo, idade, local de ocorrência e lugar de residência do falecido"

$period
[1] "2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023"

$variable
cod                                                              desc
1     343                       Número de óbitos ocorridos no ano (Pessoas)
2 1000343 Número de óbitos ocorridos no ano - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c244 = Mês de ocorrência (14):
cod      desc
1       0     Total
2    5586   Janeiro
3    5587 Fevereiro
4    5588     Março
5    5589     Abril
6    5590      Maio
7    5591     Junho
8    5592     Julho
9    5593    Agosto
10   5594  Setembro
11   5595   Outubro
12   5596  Novembro
13   5597  Dezembro
14 102885  Ignorado

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c1836 = Natureza do óbito (5):
cod        desc
1     0       Total
2 26877     Natural
3 99818 Não natural
4 26881       Outra
5 26882    Ignorado

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c2 = Sexo (4):
cod     desc
1      0    Total
2      4   Homens
3      5 Mulheres
4 104539 Ignorado

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c260 = Idade do(a) falecido(a) (81):
cod             desc
1       0            Total
2    5922   Menos de 1 ano
3    5923  Menos de 7 dias
4    5924   Menos de 1 dia
5    5925            1 dia
6    5926           2 dias
7    5927           3 dias
8    5928           4 dias
9    5929           5 dias
10   5930           6 dias
11   5931      7 a 27 dias
12   5932      7 a 13 dias
13   5933     14 a 20 dias
14   5934     21 a 27 dias
15   5935    28 a 364 dias
16   5936     28 a 59 dias
17 109550    60 a 364 dias
18   5937          2 meses
19   5938          3 meses
20   5939          4 meses
21   5940          5 meses
22   5941          6 meses
23   5942          7 meses
24   5943          8 meses
25   5944          9 meses
26   5945         10 meses
27   5946         11 meses
28   5947      1 a 14 anos
29   5948       1 a 4 anos
30   5949            1 ano
31   5950           2 anos
32   5951           3 anos
33   5952           4 anos
34   5953       5 a 9 anos
35   5954           5 anos
36   5955           6 anos
37   5956           7 anos
38   5957           8 anos
39   5958           9 anos
40   5959     10 a 14 anos
41   5960          10 anos
42   5961          11 anos
43   5962          12 anos
44   5963          13 anos
45   5964          14 anos
46   5965     15 a 84 anos
47   5966     15 a 19 anos
48   5967     20 a 24 anos
49   5968     25 a 29 anos
50   5969     30 a 34 anos
51   5970     35 a 39 anos
52   5971     40 a 44 anos
53   5972     45 a 49 anos
54   5973     50 a 54 anos
55   5974     55 a 59 anos
56   5975     60 a 64 anos
57   5976     65 a 69 anos
58   5977     70 a 74 anos
59   5978     75 a 79 anos
60   5979     80 a 84 anos
61   5980  85 anos ou mais
62 106181     85 a 89 anos
63   5981          85 anos
64   5982          86 anos
65   5983          87 anos
66   5984          88 anos
67   5985          89 anos
68 106182     90 a 94 anos
69   5986          90 anos
70   5987          91 anos
71   5988          92 anos
72   5989          93 anos
73   5990          94 anos
74 106183     95 a 99 anos
75   5991          95 anos
76   5992          96 anos
77   5993          97 anos
78   5994          98 anos
79   5995          99 anos
80   5996 100 anos ou mais
81   5997   Idade ignorada

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c257 = Local de ocorrência (6):
cod        desc
1      0       Total
2   5832    Hospital
3   5833   Domicílio
4 107166 Via pública
5 100296 Outro local
6 100297    Ignorado

$geo
cod                                             desc
1         Brazil                                       Brasil (1)
2 MetroRegionDiv Região Metropolitana e Subdivisão até 2020 (102)
3            IRD Região Integrada de Desenvolvimento até 2020 (3)
4         Region                                Grande Região (5)
5          State                        Unidade da Federação (27)
6           City                                Município (5.570)
7    MetroRegion               Região Metropolitana até 2020 (74)
8     MesoRegion                     Mesorregião Geográfica (137)
9    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 1695

$table
[1] "Tabela 1695: Divórcios concedidos em 1ª instância ou por escritura, por tempo transcorrido entre a data do casamento e a data da sentença ou da escritura, grupos de idade do marido e da mulher na data da sentença ou da escritura, regime de bens do casamento e lugar da ação do processo"

$period
[1] "2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023"

$variable
cod
1     393
2 1000393
desc
1                      Número de divórcios concedidos em ª instância ou por escritura (Unidades)
2 Número de divórcios concedidos em ª instância ou por escritura - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c345 = Tempo transcorrido entre a data do casamento e a data da sentença ou da escritura (32):
cod            desc
1     0           Total
2  8074  Menos de 1 ano
3  8075           1 ano
4  8076          2 anos
5  8077          3 anos
6  8078          4 anos
7  8079          5 anos
8  8080          6 anos
9  8081          7 anos
10 8082          8 anos
11 8083          9 anos
12 8084    10 a 14 anos
13 8085         10 anos
14 8086         11 anos
15 8087         12 anos
16 8088         13 anos
17 8089         14 anos
18 8090    15 a 19 anos
19 8091         15 anos
20 8092         16 anos
21 8093         17 anos
22 8094         18 anos
23 8095         19 anos
24 8097    20 a 25 anos
25 8098         20 anos
26 8099         21 anos
27 8100         22 anos
28 8101         23 anos
29 8102         24 anos
30 8103         25 anos
31 8104 26 anos ou mais
32 8105  Sem declaração

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c274 = Grupos de idade do marido na data da sentença (15):
cod             desc
1     0            Total
2  6121 Menos de 20 anos
3  6122     20 a 24 anos
4  6123     25 a 29 anos
5  6124     30 a 34 anos
6  6125     35 a 39 anos
7  6126     40 a 44 anos
8  6127     45 a 49 anos
9  6128     50 a 54 anos
10 6129     55 a 59 anos
11 6130     60 a 64 anos
12 6131     65 a 69 anos
13 6132     70 a 74 anos
14 6133  75 anos ou mais
15 6134   Idade ignorada

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c275 = Grupos de idade da mulher na data da sentença (15):
cod             desc
1     0            Total
2  6135 Menos de 20 anos
3  6136     20 a 24 anos
4  6137     25 a 29 anos
5  6138     30 a 34 anos
6  6139     35 a 39 anos
7  6140     40 a 44 anos
8  6141     45 a 49 anos
9  6142     50 a 54 anos
10 6143     55 a 59 anos
11 6144     60 a 64 anos
12 6145     65 a 69 anos
13 6146     70 a 74 anos
14 6147  75 anos ou mais
15 6148   Idade ignorada

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c269 = Regime de bens do casamento (5):
cod               desc
1    0              Total
2 6090 Comunhão universal
3 6091   Comunhão parcial
4 6092          Separação
5 6093     Sem declaração

$geo
cod                                             desc
1         Brazil                                       Brasil (1)
2 MetroRegionDiv Região Metropolitana e Subdivisão até 2020 (102)
3            IRD Região Integrada de Desenvolvimento até 2020 (3)
4         Region                                Grande Região (5)
5          State                        Unidade da Federação (27)
6           City                                Município (5.051)
7    MetroRegion               Região Metropolitana até 2020 (74)
8     MesoRegion                     Mesorregião Geográfica (137)
9    MicroRegion                    Microrregião Geográfica (558)

=====================================================
INFO FOR SIDRA TABLE: 4412

$table
[1] "Tabela 4412: Casamentos, por mês de ocorrência, estado civil dos cônjuges, grupos de idade dos cônjuges e lugar do registro"

$period
[1] "2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023"

$variable
cod                                                                                     desc
1    4993                                                          Número de casamentos (Unidades)
2 1004993                                     Número de casamentos - percentual do total geral (%)
3     221                      Número de casamentos entre cônjuges masculino e feminino (Unidades)
4 1000221 Número de casamentos entre cônjuges masculino e feminino - percentual do total geral (%)
5    4373                                Número de casamentos entre cônjuges masculinos (Unidades)
6 1004373           Número de casamentos entre cônjuges masculinos - percentual do total geral (%)
7    4374                                 Número de casamentos entre cônjuges femininos (Unidades)
8 1004374            Número de casamentos entre cônjuges femininos - percentual do total geral (%)

$classific_category

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c244 = Mês de ocorrência (15):
cod                     desc
1       0                    Total
2    5585 Meses de anos anteriores
3    5586                  Janeiro
4    5587                Fevereiro
5    5588                    Março
6    5589                    Abril
7    5590                     Maio
8    5591                    Junho
9    5592                    Julho
10   5593                   Agosto
11   5594                 Setembro
12   5595                  Outubro
13   5596                 Novembro
14   5597                 Dezembro
15 102885                 Ignorado

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c664 = Estado civil do primeiro cônjuge (5):
cod           desc
1     0          Total
2 32960       Solteiro
3 32961          Viúvo
4 32962     Divorciado
5 32963 Sem declaração

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c665 = Estado civil do segundo cônjuge (5):
cod           desc
1     0          Total
2 32964       Solteiro
3 32965          Viúvo
4 32966     Divorciado
5 32967 Sem declaração

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c666 = Grupo de idade do primeiro cônjuge (39):
cod             desc
1      0            Total
2  32968 Menos de 15 anos
3  32969     15 a 19 anos
4  32970          15 anos
5  32971          16 anos
6  32972          17 anos
7  32973          18 anos
8  32974          19 anos
9  32975     20 a 24 anos
10 32976          20 anos
11 32977          21 anos
12 32978          22 anos
13 32979          23 anos
14 32980          24 anos
15 32981     25 a 29 anos
16 32982          25 anos
17 32983          26 anos
18 32984          27 anos
19 32985          28 anos
20 32986          29 anos
21 32987     30 a 34 anos
22 32988          30 anos
23 32989          31 anos
24 32990          32 anos
25 32991          33 anos
26 32992          34 anos
27 32993     35 a 39 anos
28 32994          35 anos
29 32995          36 anos
30 32996          37 anos
31 32997          38 anos
32 32998          39 anos
33 32999     40 a 44 anos
34 33000     45 a 49 anos
35 33001     50 a 54 anos
36 33002     55 a 59 anos
37 33003     60 a 64 anos
38 33004  65 anos ou mais
39 33005   Idade ignorada

𝑐
𝑙
𝑎
𝑠
𝑠
𝑖
𝑓
𝑖
𝑐
𝑐
𝑎
𝑡
𝑒
𝑔
𝑜
𝑟
𝑦
classific
c
	​

ategory
c667 = Grupo de idade do segundo cônjuge (39):
cod             desc
1      0            Total
2  33006 Menos de 15 anos
3  33007     15 a 19 anos
4  33008          15 anos
5  33009          16 anos
6  33010          17 anos
7  33011          18 anos
8  33012          19 anos
9  33013     20 a 24 anos
10 33014          20 anos
11 33015          21 anos
12 33016          22 anos
13 33017          23 anos
14 33018          24 anos
15 33019     25 a 29 anos
16 33020          25 anos
17 33021          26 anos
18 33022          27 anos
19 33023          28 anos
20 33024          29 anos
21 33025     30 a 34 anos
22 33026          30 anos
23 33027          31 anos
24 33028          32 anos
25 33029          33 anos
26 33030          34 anos
27 33031     35 a 39 anos
28 33032          35 anos
29 33033          36 anos
30 33034          37 anos
31 33035          38 anos
32 33036          39 anos
33 33037     40 a 44 anos
34 33038     45 a 49 anos
35 33039     50 a 54 anos
36 33040     55 a 59 anos
37 33041     60 a 64 anos
38 33042  65 anos ou mais
39 33043   Idade ignorada

$geo
cod                                             desc
1         Brazil                                       Brasil (1)
2 MetroRegionDiv Região Metropolitana e Subdivisão até 2020 (102)
3            IRD Região Integrada de Desenvolvimento até 2020 (3)
4         Region                                Grande Região (5)
5          State                        Unidade da Federação (27)
6           City                                Município (5.243)
7    MetroRegion               Região Metropolitana até 2020 (74)
8     MesoRegion                     Mesorregião Geográfica (137)
9    MicroRegion                    Microrregião Geográfica (558)

Devise a extensively, extremely detailed and exhaustive plan on how to integrate these new tables. Plan EVERYTHING.

Anticipating age category schema harmonization, recall that our demographic_basis script uses the following approach:

Demographic Codes

RACE_CODES <- c("Branca"="Wht", "Preta"="Blk", "Amarela"="Ylw", "Parda"="Brn", "Indígena"="Ind", "Sem declaração"="Ign", "Total"="T")
SEX_CODES  <- c("Homens"="M", "Mulheres"="W", "Total"="T")

Age Band Definitions

TARGET_AGE_BANDS <- c("00_04", "05_09", "10_14", "15_19", "20_24", "25_29",
"30_39", "40_49", "50_59", "60_69", "70_79", "80p")
AGE_BAND_TOTAL_CODE <- "Tot_Raw_Age" # For extracting raw age totals from census

SIDRA Variables known to use '.' as decimal

VARS_WITH_POINT_DECIMAL <- c("Salário médio mensal", "Salário médio mensal em reais")

Census Year Strings for Filtering (to avoid double counting from source tables)

T2093_DESIRED_AGE_STRINGS <- c("0 a 4 anos", "5 a 9 anos", "10 a 14 anos", "15 a 19 anos",
"20 a 24 anos", "25 a 29 anos", "30 a 39 anos", "40 a 49 anos",
"50 a 59 anos", "60 a 69 anos", "70 a 79 anos", "80 anos ou mais")
T9606_DESIRED_AGE_STRINGS <- c("0 a 4 anos", "5 a 9 anos", "10 a 14 anos", "15 a 19 anos",
"20 a 24 anos", "25 a 29 anos", "30 a 34 anos", "35 a 39 anos",
"40 a 44 anos", "45 a 49 anos", "50 a 54 anos", "55 a 59 anos",
"60 a 64 anos", "65 a 69 anos", "70 a 74 anos", "75 a 79 anos",
"80 a 84 anos", "85 a 89 anos", "90 a 94 anos", "95 a 99 anos",
"100 anos ou mais")

Master Census Years - these are the anchor points for interpolation of shares

MASTER_CENSUS_YEARS <- c(2000, 2010, 2022)

Year for geobr calls to get municipality lists (contemporary)

GEOBR_MUNI_LIST_YEAR <- 2022