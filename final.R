## ----setup, include=FALSE-----------------------------------------------------
knitr::opts_chunk$set(echo = TRUE)

# 1. Imports
library(tidyverse)
library(lubridate)
library(hrbrthemes)
library(dataReporter)
library(patchwork)

# 2. Fonts
import_roboto_condensed()

#3. Colors
blue1<- "#6a92b9"
blue2 <- "#0B3B60"
a <- "#0B3B60"
b <- "#41678D"
c <-"#6A92B9"
d <-"#ADC3DC"
e <-"#EFF3FE"

gray1 <- "#82858c"
gray2 <- "#d4d7db"



## ----read in data-------------------------------------------------------------

# Read in data
data <- read_csv(here::here("data/finished_tax_calc.csv"))

population <- read.csv(here::here("data/population-projections-2021.csv"), sep=";")

# Subset relevant columns
df <- data %>%
  select(agegroup, race, hispan, sex, starts_with("projwt"), matches("\\d{4}$")) %>%
  select(-ends_with("growth"), -ends_with("rate"))

df$indexer <- 1:nrow(df)

# Create codebook
# makeCodebook(df, replace = TRUE)


## ----population---------------------------------------------------------------

# Get OSBM population projection totals by year

pop_df <- population %>% 
  filter(County!="Total", Race!="Total", Region!="Total", COG!="Total") %>% 
  filter(Year>=2019, Year<=2040) %>% 
  rename(year = Year)

pop_agg <- population %>% 
  filter(County!="Total", Race!="Total", Region!="Total", COG!="Total") %>% 
  group_by(Year) %>% 
  summarise(population = sum(Total)) %>% 
  filter(Year>=2019, Year<=2040) %>% 
  rename(year = Year)



## ----demographics-------------------------------------------------------------

levels <- c("Under 25", "25 to 44", "45 to 64", "Over 65")

#1.  Create base dataset for demographic trends

### 1a. Race
race <- pop_df %>% 
  group_by(Race, year) %>% 
  summarise(race_total = sum(Total))

race <- race %>% 
  group_by(year) %>% 
  summarise(total = sum(race_total)) %>% 
  merge(race, by="year") %>% 
  mutate(percent = race_total/total)

### 1b. Age
agegroup <- pop_df %>% 
  select("Age.0.to.17", "Age.18.to.24", "Age.25.to.44", "Age.45.to.64", "Age.65.Plus", "year") %>% 
  replace(is.na(.), 0) %>% 
  mutate(Age.0.to.24 = Age.0.to.17 + Age.18.to.24) %>% 
  pivot_longer(cols=c(Age.0.to.24, Age.25.to.44, Age.45.to.64, Age.65.Plus), names_to='agegroup') %>% 
  group_by(year, agegroup) %>% 
  summarise(agegroup_total = sum(value)) %>% 
  mutate(agegroup = case_when(agegroup =='Age.0.to.24' ~ 'Under 25',
                             agegroup =='Age.25.to.44' ~ "25 to 44",
                             agegroup =='Age.45.to.64' ~ "45 to 64",
                             agegroup =='Age.65.Plus'~"Over 65"),
         agegroup = factor(agegroup, levels=levels))  

agegroup <- agegroup %>% 
  group_by(year) %>% 
  summarise(total = sum(agegroup_total)) %>% 
  merge(agegroup, by="year") %>% 
  mutate(percent = agegroup_total/total)



## ----income type--------------------------------------------------------------

#2.Create base income dataset 

inc_df <- df %>%  
  select(indexer,starts_with("inc"), starts_with("projwt"), starts_with("cap_gains"), starts_with("adj_tax"), indexer) %>% 
  select(contains("20"), indexer) 

names(inc_df) <- gsub(x = names(inc_df), pattern = "cap_gains", replacement = "inccapgains")  
names(inc_df) <- gsub(x = names(inc_df), pattern = "adj_taxable_inc", replacement = "incadj_taxable_inc")  


inc_df <- inc_df %>% 
  pivot_longer(starts_with("inc"), values_to='inc', names_to=c("inctype", "year"), names_sep="_") %>% 
  pivot_longer(starts_with("proj"), values_to='weight', names_to="year2") %>% 
  mutate(year2 = str_sub(year2, 7, -1),
         inctype = str_sub(inctype, 4, -1)) %>% 
  filter(year==year2) %>% 
  mutate(weighted_inc=inc*weight) %>% 
  group_by(inctype, year) %>% 
  summarise(total_inc=sum(weighted_inc)) %>% 
  mutate(year=as.numeric(year)) %>% 
  filter(year>=2019)  

  


## ----tax liability------------------------------------------------------------
# 4. Create dataset for state tax liability over time

# 4a. Total
taxliab_df<- df %>%  
  select(starts_with("adj_nc_net_tax"), starts_with("projwt"), agegroup) %>% 
      pivot_longer(starts_with("adj_nc_net_tax"), values_to='inc', names_to="year") %>% 
      pivot_longer(starts_with("proj"), values_to='weight', names_to="year2") %>% 
  mutate(year2 = str_sub(year2, -4, -1),
         year = str_sub(year, -4, -1)) %>% 
  filter(year==year2) %>% 
  mutate(weighted_inc=inc*weight) %>% #calculate weighted income
  group_by(year) %>% 
  summarise(pop_count=sum(weight),
            total_inc=sum(weighted_inc)) %>% # compress to year and agegroup
  mutate(year=as.numeric(year)) %>% 
  filter(year>=2019) %>% 
  ungroup()



## ----graph1-------------------------------------------------------------------

# Graph 1: Demographics

## 1. Total Pop
popplot <- ggplot(pop_agg, aes(x = year, y = population)) + 
  geom_area(alpha=1 , size=.5, colour="white", fill=blue2) +
  theme_ipsum_rc(grid = "y") +
  scale_y_continuous(limits = c(0,15000000), breaks = c(0, 5000000, 10000000, 15000000), labels = c("0", "5M", "10M", "15M")) + 
  labs(x = "", y = "", title = "North Carolina's population is steadily growing", caption= "Source: Office of State Budget and Management") +
  theme(axis.title = element_blank(), legend.title = element_blank()) +
  annotate("text", x=2040, y=13500000, label = "12.7M", family='Roboto Condensed', color='#505050', fontface=2) +
  annotate("text", x=2019, y=11500000, label = "10.4M", family='Roboto Condensed', color='#505050', fontface=2)

## 2. Race
  
raceplot <- ggplot(race, aes(x = year, y = percent, groups=Race, fill=Race)) + 
  geom_area(alpha=1 , size=.5, colour="white") +
  scale_fill_manual(values=c(e,d,c,b,a), labels = c('AIAN', 'Asian', "Black", "Other", "White")) + 
  theme_ipsum_rc(grid = "y") +
  scale_y_continuous(labels = c("0%", "25%", "50%", "75%", "100%" )) +
  labs(x = "", y = "", title = "The share of White and Black residents is shrinking.", subtitle = 'People with Hispanic ethnicity have been included in broader race categories.', caption= "Source: Office of State Budget and Management") +
  theme(axis.title = element_blank(), legend.title = element_blank()) 


### 3. Age
ageplot <- ggplot(agegroup, aes(x = year, y = percent, group=agegroup, fill=agegroup)) + 
  geom_area(alpha=1 , size=.5, colour="white") +
  scale_fill_manual(values=c(e, d, c, a)) + 
  theme_ipsum_rc(grid = "y") +
  scale_y_continuous(labels = c("0%", "25%", "50%", "75%", "100%" )) +
  labs(x = "", y = "", title = "The population is getting older.", caption= "Source: Office of State Budget and Management") +
  theme(axis.title = element_blank(), legend.title = element_blank()) 



## ----graph2-------------------------------------------------------------------

# Graph 2: Incomes
## Trends in income components over time
## Nonwage vs wage only 

inc_small_df <- inc_df %>% 
  mutate(inctype=case_when((inctype=='capgains'| inctype=='div'| inctype=='int'| inctype=='rent'| inctype=='retirement'| inctype=='ss'| inctype=='unemp' | inctype=='other') ~"other", inctype=="bus"~"bus", inctype=="wage"~"wage", inctype=="farm"~"bus")) %>% 
  group_by(inctype,year) %>% 
  summarise(total_inc=sum(total_inc))

incplot_small <- ggplot(inc_small_df, aes(x = year, y = total_inc, group=inctype, fill=inctype)) + 
  geom_area(alpha=1 , size=.5, color='white') +
  scale_fill_manual(values=c(e, c, a), labels = c("Farm & Business", "Other", "Wage")) + 
  labs(fill='Income Type') +
  theme_ipsum_rc(grid = "y") +
  scale_y_continuous(breaks = c(0, 200000000000, 400000000000, 600000000000, 800000000000), labels = c("$0", "$200B", "$400B", "$600B", "$800B")) +
  labs(x = "", y = "", title = "Wages makes up the majority of people's income.", caption= "Source: Personal Income Tax Model Predictions") +
  theme(axis.title = element_blank()) 





## ----taxliab plot-------------------------------------------------------------

# Graph 4: State Tax Liability
## 4a. Trends in tax liability over time, total

label <- taxliab_df %>% 
  filter(year==2040) %>% 
  mutate(diff = (total_inc/1000000000)) %>% 
  select(diff) %>% 
  mutate(diff = round(diff, 1)) %>% 
  paste0("B") 
label <- paste0("$", label)

taxliab_plot <- ggplot(taxliab_df, aes(x = year, y = total_inc)) + 
  geom_area(alpha=1 , size=.5, colour="white", fill=blue2) +
  theme_ipsum_rc(grid = "y") +
  scale_y_continuous(breaks = c(0, 5000000000, 10000000000, 15000000000, 20000000000), labels = c("$0B", "$5B", "$10B", "$15B", "$20B")) +
  labs(x = "", y = "", title = "Tax liability is projected to be nearly $20B in 2040.") +
  theme(axis.title = element_blank(), legend.title = element_blank()) +
  annotate("text", x=2041.2, y=19800000000, label = label, family='Roboto Condensed', color='#505050', fontface=2) 
  


