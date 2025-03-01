# This function implements census population adjustment and smoothing in accordance with 
# Peter Johnson methods protocol
# still needs testing to ensure PJ protocols carried out exactly as specified
# it further extends age distributions to open age = 100+ using OPAG

library(DemoTools)
library(tidyverse)

#####

censusPop_adjust_smooth_extend_workflow_one_census <- function(dd_census_extract, 
                                                               pes_directory="dev/PES/",
                                                               nLxFemale = NULL,
                                                               nLxMale = NULL,
                                                               Age_nLx = NULL,
                                                               AgeInt_nLx = NULL,
                                                               nLxDatesIn = NULL,
                                                               AsfrMat = NULL,
                                                               AsfrDatesIn = NULL,
                                                               SRB = NULL,
                                                               SRBDatesIn = NULL,
                                                               radix = NULL,
                                                               OAnew = 105,
                                                               sub_locid_PES = NULL,
                                                               sub_locid_EduYrs = NULL,
                                                               sub_locid_DemoTools = NULL,
                                                               adjust_pes = TRUE,
                                                               adjust_smooth = TRUE,
                                                               adjust_basepop = TRUE) {
  
  
  # 1. check that data meet some basic requirements
  nids <- length(unique(dd_census_extract$id))
  maxage <- max(dd_census_extract$AgeStart)
  stopifnot(nids == 1 & maxage >= 50)
  
  # 2. census descriptors
  locid <- dd_census_extract$LocID[1]
  
  # locid used to select PES results
  locid_PES <- ifelse(is.null(sub_locid_PES), locid, sub_locid_PES)
  # locid used to select years of education by sex (for most this is the locid, but for Kosovo, for example, we need to sub Serbia)
  locid_EduYrs <- ifelse(is.null(sub_locid_EduYrs), locid, sub_locid_EduYrs)
  # locid used to select lifetable values or asfr through DemoTools functions
  locid_DemoTools <- ifelse(is.null(sub_locid_DemoTools), locid, sub_locid_DemoTools)
  
  census_refpd <- dd_census_extract$ReferencePeriod[1]
  census_reference_date <- as.numeric(dd_census_extract$TimeMid[1])
  
  # 3. load some preliminaries
  
  # covariates
  if (!exists("Covariates")) {load(paste0(pes_directory,"Covariates.RData"))}
  
  # parse years of education by sex to use as criterion for selecting levels of smoothing
  EduYrs_m <-  dplyr::filter(Covariates,LocID==locid_EduYrs, Year==max(floor(census_reference_date), 1950))$EducYrsM
  EduYrs_f <-  dplyr::filter(Covariates,LocID==locid_EduYrs, Year==max(floor(census_reference_date), 1950))$EducYrsF
  
  # if we will adjust for under/over enumeration, load those model results
  if (adjust_pes) {
    # load census enumeration model results from post-enumeration survey model
    if (!exists("TotNetEnum")) {load(paste0(pes_directory,"TotNetEnum.RData"))}  
    if (!exists("DiffNCE1")) {load(paste0(pes_directory,"DiffNCE1.RData"))}
    if (!exists("DiffNCEAbr")) {load(paste0(pes_directory,"DiffNCEAbr.RData"))}
  }
  
  # 4. Parse the census population counts by single year of age
  pop1 <- dd_census_extract %>% dplyr::filter(complete == TRUE) %>% 
    arrange(SexID, AgeStart)
  
  maxage <- ifelse(nrow(pop1) > 0, max(pop1$AgeStart), 0)

  # 5. initalize the population series
  popM <- NULL
  popF <- NULL
  Age  <- NULL
  
  # 6. Proceed with single age data if the open age group is age 50 or higher
  if (nrow(pop1) > 0 & maxage >= 50) {
    
    pop_in <- pop1 %>% 
      dplyr::filter(AgeLabel != "Total" & SexID %in% c(1,2)) %>% 
      select(SexID, AgeStart, DataValue, id)
    
    popM   <- pop_in$DataValue[pop_in$SexID ==1]
    popF   <- pop_in$DataValue[pop_in$SexID ==2]
    Age    <- pop_in$AgeStart[pop_in$SexID ==2]
    nAge   <- length(Age)
    
    
    # 6.a. collapse open age over 100 to 100+  
      if (maxage > 100) {
        popM   <- c(popM[Age < 100], sum(popM[Age >= 100]))
        popF   <- c(popF[Age < 100], sum(popF[Age >= 100]))
        Age    <- c(Age[Age<100], 100) 
        maxage <- 100
        nAge   <- length(Age)
      }
    
    # 6.b. If the open age group is larger than OpenAge5, then truncate back
      OpenAge5 <- as.integer(maxage / 5) * 5
      if (maxage > OpenAge5) {
        popM   <- c(popM[Age < OpenAge5], sum(popM[Age >= OpenAge5]))
        popF   <- c(popF[Age < OpenAge5], sum(popF[Age >= OpenAge5]))
        Age    <- c(Age[Age < OpenAge5], OpenAge5)
        maxage <- OpenAge5
        nAge   <- length(Age)
      }
      rm(OpenAge5)
    
    
    
    # 6.c. If we are adjusting for enumeration, do that now
    if (adjust_pes) {
      #Parse net census enumeration model results for the given locid and census year
      NCE_total <- dplyr::filter(TotNetEnum, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum
      NCE_m     <- dplyr::filter(DiffNCE1, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum_M_Diff
      NCE_f     <- dplyr::filter(DiffNCE1, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum_F_Diff
      NCE_age   <- dplyr::filter(DiffNCE1, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$Age
    
      # truncate sex-age specific nce diff to the ages of the available population data
      NCE_m   <- c(NCE_m[NCE_age < maxage], mean(NCE_m[NCE_age >= maxage]))
      NCE_f   <- c(NCE_f[NCE_age < maxage], mean(NCE_f[NCE_age >= maxage]))
    
    
      # Perform the adjustment per net census enumeration model results based on analysis of post-enumeration surveys
      pop_adjusted <- censusPop_adjust_nce(popM = popM,
                                           popF = popF,
                                           Age  = Age,
                                           NCE_total = NCE_total,
                                           NCE_m = NCE_m,
                                           NCE_f = NCE_f) 

      # work on the basis of the adjusted series
      popM <- pop_adjusted[[1]]
      popF <- pop_adjusted[[2]]
      
      pop_adjusted <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                 AgeStart = rep(Age,2),
                                 DataValue = c(popM, popF))

    } else { # if not adjusting for enumeration, set these objects as null and continue working on the basis of the original input
      pop_adjusted <- NULL
      NCE_total <- NA
      
      popM <- popM
      popF <- popF
    }
    # set the unsmoothed series aside for basepop later
      # if PES adjustment was used, then this is the adjusted series.  If not, it is the original series
    popM_unsmoothed <- popM
    popF_unsmoothed <- popF
      
    # 6. new Extend to ages 105+ using OPAG
      
      if (maxage < OAnew) {
        OPAG_m <- OPAG_wrapper(Pop = popM,
                               Age = Age,
                               LocID = locid_DemoTools, 
                               Year = min(floor(census_reference_date), 2019), 
                               sex = "male", 
                               nLx = nLxMale,
                               Age_nLx = Age_nLx,
                               AgeInt_nLx = AgeInt_nLx,
                               cv_tolerance = 0.75,
                               min_age_redist = min(max(Age), 65),
                               OAnew = OAnew)
        
        OPAG_f <- OPAG_wrapper(Pop = popF,
                               Age = Age,
                               LocID = locid_DemoTools, 
                               Year = min(floor(census_reference_date), 2019), 
                               sex = "female", 
                               nLx = nLxFemale,
                               Age_nLx = Age_nLx,
                               AgeInt_nLx = AgeInt_nLx,
                               cv_tolerance = 0.75,
                               min_age_redist = min(max(Age), 65),
                               OAnew = OAnew)
        
        min_age_redist <- min(OPAG_m$age_redist_start, OPAG_f$age_redist_start)
        
        popM <- OPAG_m$pop_ext
        popF <- OPAG_f$pop_ext
        Age  <- 0:OAnew
        nAge <- length(Age)
        
        pop_extended <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                   AgeStart = rep(Age,2),
                                   DataValue = c(popM, popF))
        

        
      } else { # if no extension necessary
        
        min_age_redist <- maxage
        
        popM <- popM
        popF <- popF
        
        pop_extended <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                   AgeStart = rep(Age,2),
                                   DataValue = c(popM, popF))
        
      } 

   
    # 6.d. If we are smoothing to address age heaping, do that now
    if (adjust_smooth) {
      
      # first smooth based on bachi or age ratio score for adults
      pop_smooth_adult <- getSmoothedPop1 (popM, popF, Age, 
                                           bachi_age = 23:(min(77,min_age_redist)),
                                           age_ratio_age = c(15, min(70, min_age_redist)),
                                           EduYrs = min(EduYrs_m, EduYrs_f), 
                                           subgroup = "adult") 
      
      # then smooth based on bachi or age ratio score for children
      pop_smooth_child <- getSmoothedPop1 (popM, popF, Age, 
                                           bachi_age = 3:17, 
                                           age_ratio_age = c(0,10),
                                           EduYrs = min(EduYrs_m, EduYrs_f), 
                                           subgroup = "child") 
      
      # blend the smoothed child and adult series, with transition at ages 15-19
      wts <- c(rep(1,16),0.8, 0.6, 0.4, 0.2, rep(0, max(Age)-19))
      
      popM_smoothed <- (pop_smooth_child$popM_smooth * wts) + (pop_smooth_adult$popM_smooth * (1-wts))
      popF_smoothed <- (pop_smooth_child$popF_smooth * wts) + (pop_smooth_adult$popF_smooth * (1-wts))
      
      # re-adjust to ensure that after smoothing we are still matching the total
      popM_smoothed <- popM_smoothed * sum(popM)/sum(popM_smoothed)
      popF_smoothed <- popF_smoothed * sum(popF)/sum(popF_smoothed)
      
      # work on the basis of the smooth series
      popM <- popM_smoothed
      popF <- popF_smoothed
      
      pop_smoothed <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                 AgeStart = rep(Age,2),
                                 DataValue = c(popM, popF))
      
      bachi_adult <- pop_smooth_adult$bachi
      bachi_child <- pop_smooth_child$bachi
      ageRatio_adult_orig <- pop_smooth_adult$AgeRatioScore_orig
      ageRatio_child_orig <- pop_smooth_child$AgeRatioScore_orig
      ageRatio_adult_mav2 <- pop_smooth_adult$AgeRatioScore_mav2
      ageRatio_child_mav2 <- pop_smooth_child$AgeRatioScore_mav2
      best_smooth_adult <- pop_smooth_adult$best_smooth_method
      best_smooth_child <- pop_smooth_child$best_smooth_method
      
    } else { # done for smoothing
      
      pop_smoothed <- NULL
      bachi_adult <- NA
      bachi_child <- NA
      ageRatio_adult_orig <- NA
      ageRatio_child_orig <- NA
      ageRatio_adult_mav2 <- NA
      ageRatio_child_mav2 <- NA
      best_smooth_adult <- NA
      best_smooth_child <- NA
      
      popM <- popM
      popF <- popF
    }
      
   } # end for single year data
  
  if (is.null(popM)) {  # if there are no single age data to process, then use abridged/five-year
    
    # 7. Parse the abridged series
    pop5 <- dd_census_extract %>% dplyr::filter(abridged == TRUE | five_year == TRUE) %>% 
      arrange(SexID, AgeStart)
    
    abr <- "1-4" %in% pop5$AgeLabel # identify whether the abridged series is available
    
    if (abr) {
      pop5 <- pop5 %>% dplyr::filter(abridged)
    } else {
      pop5 <- pop5 %>% dplyr::filter(five_year)
    }
    
    maxage <- ifelse(nrow(pop5) > 0, max(pop5$AgeStart), 0)
    
    # 8. Proceed with abridged/five year data if the open age group is age 50 or higher
    if (nrow(pop5) > 0 & maxage >= 50) {
      
      pop_in <- pop5 %>% 
        dplyr::filter(AgeLabel != "Total" & SexID %in% c(1,2)) %>% 
        select(SexID, AgeStart, DataValue, id)
      
      popM   <- pop_in$DataValue[pop_in$SexID ==1]
      popF   <- pop_in$DataValue[pop_in$SexID ==2]
      Age5   <- pop_in$AgeStart[pop_in$SexID ==2]
      nAge   <- length(Age5)

      # 8.a. collapse open age over 100 to 100+  
      if (maxage > 100) {
        popM   <- c(popM[Age5 < 100], sum(popM[Age5 >= 100]))
        popF   <- c(popF[Age5 < 100], sum(popF[Age5 >= 100]))
        Age5    <- c(Age5[Age5<100], 100) 
        maxage <- 100
        nAge   <- length(Age5)
      }
      
      # 8.b. If we are adjusting for enumeration, do that now
      if (adjust_pes) {
        
      # Parse net census enumeration model results for the given locid and census year
      NCE_total <- dplyr::filter(TotNetEnum, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum
      NCE_m     <- dplyr::filter(DiffNCEAbr, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum_M_Diff
      NCE_f     <- dplyr::filter(DiffNCEAbr, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$NetEnum_F_Diff
      NCE_age   <- dplyr::filter(DiffNCEAbr, LocID == locid_PES, Year == max(floor(census_reference_date), 1950))$Age
      
        # truncate sex-age specific nce diff to the ages of the available population data
        NCE_m   <- c(NCE_m[NCE_age < maxage], mean(NCE_m[NCE_age >= maxage]))
        NCE_f   <- c(NCE_f[NCE_age < maxage], mean(NCE_f[NCE_age >= maxage]))
        
        if (!abr) { # if only five year values, then collapse the adjustment for the first age group
          NCE_m <- c(0.2 * NCE_m[1] + 0.8 * NCE_m[2], NCE_m[3:length(NCE_m)])
          NCE_f <- c(0.2 * NCE_f[1] + 0.8 * NCE_f[2], NCE_f[3:length(NCE_f)])
        }
      
      # 8.c. Perform adjustment per net census enumeration model results based on analysis of post-enumeration surveys
      pop_adjusted <- censusPop_adjust_nce(popM = popM,
                                               popF = popF,
                                               Age  = Age5,
                                               NCE_total = NCE_total,
                                               NCE_m = NCE_m,
                                               NCE_f = NCE_f) 
      
      # work on the basis of the adjusted series
      popM <- pop_adjusted[[1]]
      popF <- pop_adjusted[[2]]
      
      pop_adjusted <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                 AgeStart = rep(Age5,2),
                                 DataValue = c(popM, popF))
      
      } else { # if not adjusting for enumeration, set these objects as null and continue working on the basis of the original input
        pop_adjusted <- NULL
        NCE_total <- NA
        
        popM <- popM
        popF <- popF
      } # end PES adjustment
      
      # set the unsmoothed series aside for basepop later
      popM_unsmoothed <- DemoTools::graduate_mono(Value = popM, Age = Age5, AgeInt = DemoTools::age2int(Age5), OAG = TRUE)
      popF_unsmoothed <- DemoTools::graduate_mono(Value = popF, Age = Age5, AgeInt = DemoTools::age2int(Age5), OAG = TRUE)
      
      
      # 8. NEW extend to 105+
      if (maxage < OAnew) {
        OPAG_m <- OPAG_wrapper(Pop = popM,
                               Age = Age5,
                               LocID = locid_DemoTools, 
                               Year = min(floor(census_reference_date), 2019), 
                               sex = "male", 
                               nLx = nLxMale,
                               Age_nLx = Age_nLx,
                               AgeInt_nLx = AgeInt_nLx,
                               cv_tolerance = 0.75,
                               min_age_redist = min(max(Age5), 65),
                               OAnew = OAnew)
        
        OPAG_f <- OPAG_wrapper(Pop = popF,
                               Age = Age5,
                               LocID = locid_DemoTools, 
                               Year = min(floor(census_reference_date), 2019), 
                               sex = "female", 
                               nLx = nLxFemale,
                               Age_nLx = Age_nLx,
                               AgeInt_nLx = AgeInt_nLx,
                               cv_tolerance = 0.75,
                               min_age_redist = min(max(Age5), 65),
                               OAnew = OAnew)
        
        min_age_redist <- min(OPAG_m$age_redist_start, OPAG_f$age_redist_start)
        
        popM <- OPAG_m$pop_ext
        popF <- OPAG_f$pop_ext
        Age5  <- OPAG_m$Age_ext
        nAge <- length(Age5)
        
        pop_extended <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                   AgeStart = rep(Age5,2),
                                   DataValue = c(popM, popF))
        
        
        
      } else { # if no extension necessary
        
        min_age_redist <- maxage
        
        popM <- popM
        popF <- popF
        
        pop_extended <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                   AgeStart = rep(Age5,2),
                                   DataValue = c(popM, popF))
        
      } 
      
      
      # 8.d. If we are smoothing to address age heaping, do that now
      if (adjust_smooth) {
        
        # first smooth based age ratio score for adults
        pop_smooth_adult <- getSmoothedPop5(popM, popF, Age5, 
                                            age_ratio_age = c(15, min(70, min_age_redist)),
                                            EduYrs = min(EduYrs_m, EduYrs_f), 
                                            subgroup = "adult") 
        
        # then smooth based on age ratio score for children
        pop_smooth_child <- getSmoothedPop5(popM, popF, Age5, 
                                            age_ratio_age = c(0, 10),
                                            EduYrs = min(EduYrs_m, EduYrs_f), 
                                            subgroup = "child") 
        
        # blend the smoothed child and adult series, with transition at ages 15-19
        wts <- c(rep(1,16),0.8, 0.6, 0.4, 0.2, rep(0, max(Age5)-19))
        
        popM_smoothed <- (pop_smooth_child$popM_smooth * wts) + (pop_smooth_adult$popM_smooth * (1-wts))
        popF_smoothed <- (pop_smooth_child$popF_smooth * wts) + (pop_smooth_adult$popF_smooth * (1-wts))
        
        # re-adjust to ensure that after smoothing we are still matching the total
        popM_smoothed <- popM_smoothed * sum(popM)/sum(popM_smoothed)
        popF_smoothed <- popF_smoothed * sum(popF)/sum(popF_smoothed)
        
        # work on the basis of the smooth series
        popM <- popM_smoothed
        popF <- popF_smoothed
        
        Age <- (1:length(popM))-1
        nAge <- length(Age)
        
        pop_smoothed <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                                   AgeStart = rep(Age,2),
                                   DataValue = c(popM, popF))
        
        bachi_adult <- NA # no bachi for 5-year data
        bachi_child <- NA
        ageRatio_adult_orig <- pop_smooth_adult$AgeRatioScore_orig
        ageRatio_child_orig <- pop_smooth_child$AgeRatioScore_orig
        ageRatio_adult_mav2 <- pop_smooth_adult$AgeRatioScore_mav2
        ageRatio_child_mav2 <- pop_smooth_child$AgeRatioScore_mav2
        best_smooth_adult <- pop_smooth_adult$best_smooth_method
        best_smooth_child <- pop_smooth_child$best_smooth_method
        
      } else { # done for smoothing
        
        pop_smoothed <- NULL
        bachi_adult <- NA
        bachi_child <- NA
        ageRatio_adult_orig <- NA
        ageRatio_child_orig <- NA
        ageRatio_adult_mav2 <- NA
        ageRatio_child_mav2 <- NA
        best_smooth_adult <- NA
        best_smooth_child <- NA
        
        # graduate the extended series
        popM <- DemoTools::graduate_mono(popM, Age = Age5, AgeInt = DemoTools::age2int(Age5))
        popF <- DemoTools::graduate_mono(popF, Age = Age5, AgeInt = DemoTools::age2int(Age5))
        Age  <- 0:max(Age5)
        nAge <- length(Age)
      }
      
    } # end for five-year data
    } # end for if no single-age data
  
        
  # 9. basepop adjustment for missing children
    if (adjust_basepop) {

      # group to abridged age groups
      popM_abr <- DemoTools::single2abridged(popM)
      popF_abr <- DemoTools::single2abridged(popF)
      Age_abr  <- as.numeric(row.names(popM_abr))
      
      # run basepop_five()
      BP1 <- DemoTools::basepop_five(location = locid_DemoTools,
                                            refDate = census_reference_date,
                                            Females_five = popF_abr,
                                            Males_five = popM_abr, 
                                            nLxFemale = nLxFemale,
                                            nLxMale   = nLxMale,
                                            nLxDatesIn = nLxDatesIn,
                                            AsfrMat = AsfrMat,
                                            AsfrDatesIn = AsfrDatesIn,
                                            SRB = SRB,
                                            SRBDatesIn = SRBDatesIn,
                                            radix = radix,
                                            verbose = FALSE)
      
      # graduate result to single year of age
      popM_BP1 <- DemoTools::graduate_mono(Value = BP1[[2]], Age = Age_abr, AgeInt = DemoTools::age2int(Age_abr), OAG = TRUE)
      popF_BP1 <- DemoTools::graduate_mono(Value = BP1[[1]], Age = Age_abr, AgeInt = DemoTools::age2int(Age_abr), OAG = TRUE)
      
      # what is the minimum age at which BP1 is higher than input population for both males and females
      BP1_higher <- popM_BP1 > popM & popF_BP1 > popF
      minLastBPage1 <- min(Age[!BP1_higher],10) - 1

      # splice the BP1 series for ages at or below minLastBPage1 with unsmoothed single age series to age 15 and smoothed series thereafter
      popM_BP2 <- c(popM_BP1[Age <= minLastBPage1], popM_unsmoothed[Age > minLastBPage1 & Age < 15], popM[Age >= 15]) 
      popF_BP2 <- c(popF_BP1[Age <= minLastBPage1], popF_unsmoothed[Age > minLastBPage1 & Age < 15], popF[Age >= 15]) 
      
      # if we are smoothing, then smooth BP2 using the best method from child smoothing before
      if (adjust_smooth) {
        adj_method <- pop_smooth_child$best_smooth_method
        
        if (substr(adj_method, 1, 8) == "bestMavN") { # if the best smoothing was mav on one year data
          mavN <- as.numeric(substr(adj_method, nchar(adj_method)-1, nchar(adj_method)))
          popM_BP3_mav <- mavPop1(popM_BP2, Age)
          popM_BP3     <- unlist(select(popM_BP3_mav$MavPopDF, !!paste0("Pop", mavN)))
          popF_BP3_mav <- mavPop1(popF_BP2, Age)
          popF_BP3     <- unlist(select(popF_BP3_mav$MavPopDF, !!paste0("Pop", mavN)))
        } else { # if the best smoothing was on five-year data
          
          popM5_BP2 <- DemoTools::groupAges(popM_BP2, N=5)
          popF5_BP2 <- DemoTools::groupAges(popF_BP2, N=5)
          Age5      <- seq(0,max(Age_abr),5)
          
          bestGrad5 <- as.numeric(substr(adj_method, nchar(adj_method), nchar(adj_method)))
          
          if (bestGrad5 == 1) {
            popM_BP3 <- DemoTools::graduate_mono(popM5_BP2, AgeInt = DemoTools::age2int(Age5), Age = Age5, OAG = TRUE)
            popF_BP3 <- DemoTools::graduate_mono(popF5_BP2, AgeInt = DemoTools::age2int(Age5), Age = Age5, OAG = TRUE)
          }
          if (bestGrad5 == 2) {
            popM5_BP2_mav2 <- DemoTools::smooth_age_5(popM5_BP2, Age5, method = "MAV", n = 2)
            popF5_BP2_mav2 <- DemoTools::smooth_age_5(popF5_BP2, Age5, method = "MAV", n = 2)
            popM_BP3 <- DemoTools::graduate_mono(popM5_BP2_mav2, AgeInt = DemoTools::age2int(Age5), Age = Age5, OAG = TRUE)
            popF_BP3 <- DemoTools::graduate_mono(popF5_BP2_mav2, AgeInt = DemoTools::age2int(Age5), Age = Age5, OAG = TRUE)
          }
          
        }
        popM_BP3 <- c(popM_BP3[Age < 15], popM[Age >=15])
        popF_BP3 <- c(popF_BP3[Age < 15], popF[Age >=15])
        
      } else { # if no smoothing then BP3 = BP2
        popM_BP3 <- popM_BP2
        popF_BP3 <- popF_BP2
        
      }
      
      # what is the minimum age at which BP1 is higher than BP3 for both males and females
      BP1_higher <- popM_BP1 >= popM_BP3 & popF_BP1 >= popF_BP3 
      minLastBPage3 <- min(Age[!BP1_higher],10) - 1
      
      # splice the BP1 up to age minLastBPage3 with the BP3
      popM_BP4 <- c(popM_BP1[Age <= minLastBPage3], popM_BP3[Age > minLastBPage3 & Age < 15], popM[Age >= 15])
      popF_BP4 <- c(popF_BP1[Age <= minLastBPage3], popF_BP3[Age > minLastBPage3 & Age < 15], popF[Age >= 15])
      
      pop_basepop <- data.frame(SexID = rep(c(rep(1,nAge),rep(2,nAge)),4),
                                AgeStart = rep(Age,8),
                                BPLabel = c(rep("BP1",nAge*2),
                                           rep("BP2",nAge*2),
                                           rep("BP3",nAge*2),
                                           rep("BP4",nAge*2)),
                                DataValue = c(popM_BP1, popF_BP1,
                                              popM_BP2, popF_BP2,
                                              popM_BP3, popF_BP3,
                                              popM_BP4, popF_BP4))

      popM <- popM_BP4
      popF <- popF_BP4
      
    } else { # if we are not doing basepop adjustment
      
      pop_basepop <- NULL
      
      popM <- popM
      popF <- popF
      
    }
        
  # create a data frame with the final output data
  Age <- 0:OAnew
  nAge <- length(Age)
  census_pop_out <- data.frame(SexID = c(rep(1,nAge),rep(2,nAge)),
                               AgeStart = rep(Age,2),
                               DataValue = c(popM, popF))
  
  # compile all of the outputs
  census_adjust_smooth_extend_out <- list(LocID = locid,
                                          LocName = dd_census_extract$LocName[1],
                                          census_reference_period = census_refpd,
                                          census_reference_date = census_reference_date,
                                          census_data_source = dd_census_extract$id[1],
                                          DataCatalogID = dd_census_extract$DataCatalogID[1],
                                          pes_adjustment = NCE_total,
                                          best_smooth_adult = best_smooth_adult,
                                          best_smooth_child = best_smooth_child,
                                          bachi_adult = bachi_adult,
                                          bachi_child = bachi_child,
                                          ageRatio_adult_orig = ageRatio_adult_orig,
                                          ageRatio_child_orig = ageRatio_child_orig,
                                          ageRatio_adult_mav2 = ageRatio_adult_mav2,
                                          ageRatio_child_mav2 = ageRatio_child_mav2,
                                          EduYrs = min(EduYrs_m, EduYrs_f),
                                          census_pop_in = pop_in,
                                          pop_adjusted = pop_adjusted,
                                          pop_extended = pop_extended,
                                          pop_smoothed = pop_smoothed,
                                          pop_basepop = pop_basepop,
                                          census_pop_out = census_pop_out) 
  
  return(census_adjust_smooth_extend_out)  
  
}


