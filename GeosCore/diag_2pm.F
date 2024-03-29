!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !MODULE: diag_2pm.F
!
! !DESCRIPTION: Subroutine DIAG\_2PM constructs the diagnostic flag arrays:
!
! \begin{itemize}
! \item LTJV: J-values (ND22)
! \item LTOH: OH concentrations  (ND43)
! \item LTHO2: HO2 concentrations (ND43)
! \item LTOTH: used for tracers (ND45)
! \end{itemize}
!
!  These arrays are either 1 (if it is within a certain time interval)   
!  or 0 (if it is not within a certain time interval).  The limits of
!  the time intervals for CTOTH and CTJV are now defined in input.geos
!  The arrays CTOTH, CTOH, CTJV count the number of times the 
!  diagnostics are accumulated for each grid box (i.e LTOTH is 1)
!\\
!\\
! !INTERFACE:
!
      SUBROUTINE DIAG_2PM( State_Met )
!
! !USES:
!
      USE CHEMGRID_MOD,       ONLY : ITS_IN_THE_CHEMGRID
      USE CMN_DIAG_MOD             ! HR_OH1, HR_OH2, etc.
      USE CMN_SIZE_MOD             ! Size parameters
      USE DIAG_MOD,           ONLY : LTJV, LTOH, LTHO2, LTO1D, LTO3P
#if defined( BPCH_DIAG )
      USE DIAG_MOD,           ONLY : LTOTH, CTOTH
      USE DIAG_MOD,           ONLY : CTJV,  CTOH, CTHO2, CTO1D, CTO3P
      USE DIAG_MOD,           ONLY : CTO3_24h
#endif
      USE PRECISION_MOD            ! For GEOS-Chem Precision (fp)
      USE State_Met_Mod,      ONLY : MetState
      USE TIME_MOD,           ONLY : GET_LOCALTIME
      USE TIME_MOD,           ONLY : ITS_TIME_FOR_DIAG
      USE TIME_MOD,           ONLY : ITS_TIME_FOR_CHEM
      USE TIME_MOD,           ONLY : GET_ELAPSED_MIN
      USE TIME_MOD,           ONLY : GET_TS_DIAG

      IMPLICIT NONE
!
! !INPUT PARAMETERS: 
!
      TYPE(MetState), INTENT(IN)  :: State_Met   ! Meteorology State object
!
! !REMARKS:
!  For now use GET_LOCALTIME( I, 1, 1 ) which will be independent of J and L
!  for a pure cartesian grid.  This may need to be revisited once G-C is
!  interfaced into a GCM.
!
! !REVISION HISTORY:
!  26 Mar 1999 - R. Yantosca - Initial version
!  (1 ) Now use F90 syntax (bmy, 3/26/99)
!  (2 ) Now reference LTNO2, CTNO2, LTHO2, CTHO2 arrays from "diag_mod.f".  
!        Updated comments, cosmetic changes.  (rvm, bmy, 2/27/02)
!  (3 ) Now removed NMIN from the arg list.  Now use functions GET_LOCALTIME,
!        ITS_TIME_FOR_CHEM, ITS_TIME_FOR_DYN from "time_mod.f" (bmy, 2/11/03)
!  (4 ) Now rewritten using a parallel DO-loop (bmy, 7/20/04)
!  (5 ) Now account for the time spent in the troposphere for ND43 and ND45
!        pure O3.  Now only accumulate counter for 3D pure O3 in ND45 if
!        it's a chemistry timestep. (phs, 1/24/07)
!  (6 ) Added 3D counter for ND65 and 03 in ND47 (phs, 11/17/08)
!  (7 ) Change re-initialization of ND45: only at the timestep after the 
!       diagnostics are accumulated. Add ITS_AFTER_DIAG and PREV_TS variables.
!       (ccc, 6/12/09)
!  (8 ) Add LTO3 to accumulate O3 in ND45 at the same place as the
!        chemistry (ccc, 7/17/09)
!  01 Mar 2012 - R. Yantosca - Now use GET_LOCALTIME(I,J,L) from time_mod.F90
!  02 Apr 2013 - M. Payer    - Remove code for LTNO, LTNO2, and LTNO3. These
!                              are no longer needed because NO, NO2, and NO3
!                              are now tracers.
!  20 Aug 2013 - R. Yantosca - Removed "define.h", this is now obsolete
!  08 Nov 2013 - M. Sulprizio- Removed CTO3 and LTO3. They are no longer used
!                              because O3 is now a tracer.
!  10 Nov 2014 - M. Yannetti - Added PRECISION_MOD
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      LOGICAL :: IS_ND22, IS_ND43, IS_ND45, IS_ND45_O3
      LOGICAL :: IS_ND47, IS_ND65, ITS_AFTER_DIAG
      LOGICAL :: IS_CHEM
      INTEGER :: I,       J,       L
      INTEGER :: PREV_TS
      REAL(fp)  :: LT(IIPAR)

      !=================================================================
      ! DIAG_2PM begins here!
      !=================================================================

      ! Set logical flags
      IS_ND22    = ( ND22 > 0 .and. ITS_TIME_FOR_CHEM() )
      IS_ND45    = ( ND45 > 0                           )
      IS_ND43    = ( ND43 > 0 .and. ITS_TIME_FOR_CHEM() )
      IS_ND47    = ( ND47 > 0                           ) 
      IS_ND65    = ( ND65 > 0                           )
      IS_CHEM    = ( ITS_TIME_FOR_CHEM() )

      ! Calculate time at previous timestep for the diagnostics (ccc, 6/12/09)
      PREV_TS    = GET_ELAPSED_MIN()

      ! Indicate if we accumulated diagnostics at the previous timestep.
      ! (ccc, 6/12/09)
      ITS_AFTER_DIAG = ( MOD(PREV_TS, GET_TS_DIAG() ) == 0 )

      ! Pre-compute local time 
      DO I = 1, IIPAR
         LT(I) = GET_LOCALTIME( I, 1, 1 )
      ENDDO

!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( I, J, L )
      DO J = 1, JJPAR
      DO I = 1, IIPAR

#if defined( BPCH_DIAG )
         !-----------------------------
         ! ND45 -- mixing ratios
         !-----------------------------
         IF ( IS_ND45 ) THEN

            ! Change initialization of LTOTH: only on timestep after saving
            ! diagnostics.(ccc, 6/12/09)
            IF ( ITS_AFTER_DIAG ) THEN
               LTOTH(I,J) = 0
            ENDIF

            ! Archive if we fall w/in the local time limits
            IF ( LT(I) >= HR1_OTH .and. LT(I) <= HR2_OTH ) THEN

               ! We only count the cells that are for the first time 
               ! between the time limits since the last accumulation of
               ! the diagnostics. (ccc, 7/17/09)
	       IF ( LTOTH(I, J) == 0 ) THEN
                  CTOTH(I,J) = CTOTH(I,J) + 1
	       ENDIF
               LTOTH(I,J) = 1

            ENDIF
         ENDIF
         
         !-----------------------------
         ! ND47_O3 / ND65 -- "chemistry all day long" counter
         !-----------------------------
         IF ( IS_ND47 .OR. IS_ND65 ) THEN

               ! Counter for # of O3 boxes in the chemgrid (phs, 11/17/08)
               DO L = 1, MAX( LD47, LD65 )
                 IF ( IS_CHEM .and.
     &                ITS_IN_THE_CHEMGRID( I, J, L, State_Met )) THEN
                     CTO3_24h(I,J,L) = CTO3_24h(I,J,L) + 1
                  ENDIF
               ENDDO

         ENDIF
#endif

         !-----------------------------
         ! ND22 -- J-Value diagnostic
         !-----------------------------
         IF ( IS_ND22 ) THEN

            ! Archive if we fall w/in the local time limits
            IF ( LT(I) >= HR1_JV .and. LT(I) <= HR2_JV ) THEN
               LTJV(I,J) = 1
#if defined( BPCH_DIAG )
               CTJV(I,J) = CTJV(I,J) + 1
#endif
            ELSE
               LTJV(I,J) = 0
            ENDIF
         ENDIF

         !-----------------------------
         ! ND43 -- OH, HO2
         !-----------------------------
         IF ( IS_ND43 ) THEN

            ! LTOH denotes where LT is between HR1_OH and HR2_OH
            ! CTOH counts the times when LT was between HR1_OH and HR2_OH
            ! Now set LTHO2, CTHO2 based on the OH times (rvm, bmy, 2/27/02)
            IF ( LT(I) >= HR1_OH .and. LT(I) <= HR2_OH ) THEN  
               LTOH(I,J)  = 1
               LTHO2(I,J) = 1
               LTO1D(I,J) = 1
               LTO3P(I,J) = 1

#if defined( BPCH_DIAG )
               ! Counters for # of OH, HO2 boxes in the chemgrid (phs, 1/24/07)
               DO L = 1, LD43 
                  IF ( ITS_IN_THE_CHEMGRID( I, J, L, State_Met ) ) THEN
                     CTOH(I,J,L)  = CTOH(I,J,L)  + 1
                     CTHO2(I,J,L) = CTHO2(I,J,L) + 1
                     CTO1D(I,J,L) = CTO1D(I,J,L) + 1
                     CTO3P(I,J,L) = CTO3P(I,J,L) + 1
                  ENDIF
               ENDDO
#endif

            ELSE
               LTOH(I,J)  = 0
               LTHO2(I,J) = 0
               LTO1D(I,J) = 0
               LTO3P(I,J) = 0
            ENDIF
         ENDIF

      ENDDO
      ENDDO
!$OMP END PARALLEL DO

      END SUBROUTINE DIAG_2PM
!EOC
