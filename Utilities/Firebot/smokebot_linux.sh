#!/bin/bash

# Smokebot
# This script is a simplified version of Kris Overholt's firebot script.
# It runs the smokeview verification suite (not FDS) on the latest
# revision of the repository.  It does not erase files that are not
# the repository.  This allows one to test working files before they
# have been committed.  

#  ===================
#  = Input variables =
#  ===================

FIREBOT_QUEUE=smokebot
while getopts 'q:' OPTION
do
case $OPTION in
  q)
   FIREBOT_QUEUE="$OPTARG"
   ;;
esac
done
shift $(($OPTIND-1))

#mailTo="kevin.mcgrattan@nist.gov, randall.mcdermott@nist.gov, glenn.forney@nist.gov, craig.weinschenk@nist.gov, kristopher.overholt@nist.gov"
mailTo="glenn.forney@nist.gov, koverholt@gmail.com"

FIREBOT_USERNAME="`whoami`"

FIREBOT_HOME_DIR="/home/$FIREBOT_USERNAME"
FIREBOT_DIR="$FIREBOT_HOME_DIR/SMOKEBOT"
FDS_SVNROOT="$FIREBOT_HOME_DIR/FDS-SMV"
CFAST_SVNROOT="$FIREBOT_HOME_DIR/cfast"
ERROR_LOG=$FIREBOT_DIR/output/errors
WARNING_LOG=$FIREBOT_DIR/output/warnings
GUIDE_DIR=$FIREBOT_DIR/guides

export JOBPREFIX=SB_

#  =============================================
#  = Firebot timing and notification mechanism =
#  =============================================

# This routine checks the elapsed time of Firebot.
# If Firebot runs more than 12 hours, an email notification is sent.
# This is a notification only and does not terminate Firebot.
# This check runs during Stages 3 and 5.

# Start firebot timer
START_TIME=$(date +%s)

# Set time limit (43,200 seconds = 12 hours)
TIME_LIMIT=43200
TIME_LIMIT_EMAIL_NOTIFICATION="unsent"

check_time_limit()
{
   if [ "$TIME_LIMIT_EMAIL_NOTIFICATION" == "sent" ]
   then
      # Continue along
      :
   else
      CURRENT_TIME=$(date +%s)
      ELAPSED_TIME=$(echo "$CURRENT_TIME-$START_TIME"|bc)

      if [ $ELAPSED_TIME -gt $TIME_LIMIT ]
      then
         echo -e "smokebot has been running for more than 12 hours in Stage ${TIME_LIMIT_STAGE}. \n\nPlease ensure that there are no problems. \n\nThis is a notification only and does not terminate smokebot." | mail -s "smokebot Notice: smokebot has been running for more than 12 hours." $mailTo > /dev/null
         TIME_LIMIT_EMAIL_NOTIFICATION="sent"
      fi
   fi
}

#  ========================
#  = Additional functions =
#  ========================

set_files_world_readable()
{
   cd $FDS_SVNROOT
   chmod -R go+r *
}

clean_firebot_history()
{
   # Clean Firebot metafiles
   cd $FIREBOT_DIR
   rm -f output/* > /dev/null
}

#  ========================
#  ========================
#  = Firebot Build Stages =
#  ========================
#  ========================

# Initialize stage success flags to false

stage0_success=false
stage1_success=false
stage2a_success=false
stage2b_success=false
stage3_success=false
stage4a_success=false
stage4b_success=false
stage5_success=false
stage6a_success=false
stage6b_success=false
stage6c_success=false
stage6d_success=false
stage6e_success=false
stage6f_success=false
stage7a_success=false
stage7b_success=false

#  ===================================
#  = Stage 0 - External dependencies =
#  ===================================

update_and_compile_cfast()
{
   cd $FIREBOT_HOME_DIR

   # Check to see if CFAST repository exists
   if [ -e "$CFAST_SVNROOT" ]
   # If yes, then update the CFAST repository and compile CFAST
   then
      echo "Updating and compiling CFAST:" > $FIREBOT_DIR/output/stage0_cfast
      cd $CFAST_SVNROOT/CFAST
      
      # Update to latest SVN revision
      svn update >> $FIREBOT_DIR/output/stage0_cfast 2>&1
      
   # If no, then checkout the CFAST repository and compile CFAST
   else
      echo "Downloading and compiling CFAST:" > $FIREBOT_DIR/output/stage0_cfast
      mkdir -p $CFAST_SVNROOT
      cd $CFAST_SVNROOT

      svn co https://cfast.googlecode.com/svn/trunk/cfast/trunk/CFAST CFAST >> $FIREBOT_DIR/output/stage0_cfast 2>&1
      
   fi
    # Build CFAST
    cd $CFAST_SVNROOT/CFAST/intel_linux_64
    make --makefile ../makefile clean &> /dev/null
    ./make_cfast.sh >> $FIREBOT_DIR/output/stage0_cfast 2>&1

   # Check for errors in CFAST compilation
   cd $CFAST_SVNROOT/CFAST/intel_linux_64
   if [ -e "cfast6_linux_64" ]
   then
      stage0_success=true
   else
      echo "Errors from Stage 0 - CFAST:" >> $ERROR_LOG
      echo "CFAST failed to compile" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage0_cfast >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

}

#  ============================
#  = Stage 1 - SVN operations =
#  ============================

clean_svn_repo()
{
   # Check to see if FDS repository exists
   if [ -e "$FDS_SVNROOT" ]
   then
   # If not, create FDS repository and checkout
     dummy=true
   else
      echo "Downloading FDS repository:" >> $FIREBOT_DIR/output/stage1 2>&1
      cd $FIREBOT_HOME_DIR
      svn co https://fds-smv.googlecode.com/svn/trunk/FDS/trunk/ FDS-SMV >> $FIREBOT_DIR/output/stage1 2>&1
   fi
}

do_svn_checkout()
{
   cd $FDS_SVNROOT
   # If an SVN revision number is specified, then get that revision

   echo "Checking out latest revision." >> $FIREBOT_DIR/output/stage1 2>&1
   svn update >> $FIREBOT_DIR/output/stage1 2>&1
   SVN_REVISION=`tail -n 1 $FIREBOT_DIR/output/stage1 | sed "s/[^0-9]//g"`
}

check_svn_checkout()
{
   cd $FDS_SVNROOT
   # Check for SVN errors
   if [[ `grep -E 'Updated|At revision' $FIREBOT_DIR/output/stage1 | wc -l` -ne 1 ]];
   then
      echo "Errors from Stage 1 - SVN operations:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage1 >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      email_build_status
      exit
   else
      stage1_success=true
   fi
}

#  =============================
#  = Stage 2a - Compile FDS DB =
#  =============================

compile_fds_db()
{
   # Clean and compile FDS DB
   cd $FDS_SVNROOT/FDS_Compilation/intel_linux_64_db
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage2a
}

check_compile_fds_db()
{
   # Check for errors in FDS DB compilation
   cd $FDS_SVNROOT/FDS_Compilation/intel_linux_64_db
   if [ -e "fds_intel_linux_64_db" ]
   then
      stage2a_success=true
   else
      echo "Errors from Stage 2a - Compile FDS DB:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage2a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 2a warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ================================================

wait_verification_cases_short_start()
{
   # Scans qstat and waits for verification cases to start
   while [[ `qstat | grep $(whoami) | grep Q` != '' ]]; do
      JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | grep Q | wc -l`
      echo "Waiting for ${JOBS_REMAINING} verification cases to start." >> $FIREBOT_DIR/output/stage3
      TIME_LIMIT_STAGE="3"
      check_time_limit
      sleep 30
   done
}

wait_verification_cases_short_end()
{
   # Scans qstat and waits for verification cases to end
   while [[ `qstat | grep $(whoami)` != '' ]]; do
      JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | wc -l`
      echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage3
      TIME_LIMIT_STAGE="3"
      check_time_limit
      sleep 30
   done
}

run_verification_cases_short()
{

   #  =====================
   #  = Run all SMV cases =
   #  =====================

   cd $FDS_SVNROOT/Verification/scripts

   # Submit SMV verification cases and wait for them to start (run SMV cases in debug mode on firebot queue)
   echo 'Running SMV verification cases:' >> $FIREBOT_DIR/output/stage3 2>&1
   ./Run_SMV_Cases.sh -d -q $FIREBOT_QUEUE >> $FIREBOT_DIR/output/stage3 2>&1
   wait_verification_cases_short_start

   # Wait some additional time for all cases to start
   sleep 30

   # Stop all cases
   ./Run_SMV_Cases.sh -d -s >> $FIREBOT_DIR/output/stage3 2>&1
   echo "" >> $FIREBOT_DIR/output/stage3 2>&1

   # Wait for SMV verification cases to end
   wait_verification_cases_short_end

   #  ======================
   #  = Remove .stop files =
   #  ======================

   # Remove all .stop and .err files from Verification directories (recursively)
   cd $FDS_SVNROOT/Verification
   find . -name '*.stop' -exec rm -f {} \;
   find . -name '*.err' -exec rm -f {} \;
   find Visualization -name '*.smv' -exec rm -f {} \;
   find WUI -name '*.smv' -exec rm -f {} \;
}

check_verification_cases_short()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage3` == "" ]] && \
      [[ `grep ERROR: -rI *` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI *` == "" ]] && \
      [[ `grep -A 20 forrtl -rI *` == "" ]]
   then
      stage3_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage3 > $FIREBOT_DIR/output/stage3_errors
      grep ERROR: -rI * >> $FIREBOT_DIR/output/stage3_errors
      grep 'STOP: Numerical' -rI * >> $FIREBOT_DIR/output/stage3_errors
      grep -A 20 forrtl -rI * >> $FIREBOT_DIR/output/stage3_errors
      
      echo "Errors from Stage 3 - Run verification cases (short run):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage3_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 4a - Compile FDS release =
#  ==================================

compile_fds()
{
   # Clean and compile FDS
   cd $FDS_SVNROOT/FDS_Compilation/intel_linux_64
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage4a
}

check_compile_fds()
{
   # Check for errors in FDS compilation
   cd $FDS_SVNROOT/FDS_Compilation/intel_linux_64
   if [ -e "fds_intel_linux_64" ]
   then
      stage4a_success=true
   else
      echo "Errors from Stage 4a - Compile FDS release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage4a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # 'performing multi-file optimizations' and 'generating object file' are part of a normal compile
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 4a warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ===============================================
#  = Stage 5 - Run verification cases (long run) =
#  ===============================================

wait_verification_cases_long_end()
{
   # Scans qstat and waits for verification cases to end
   while [[ `qstat | grep $(whoami)` != '' ]]; do
      JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | wc -l`
      echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage5
      TIME_LIMIT_STAGE="5"
      check_time_limit
      sleep 60
   done
}

run_verification_cases_long()
{
   # Start running all SMV verification cases (run all cases on firebot queue)
   cd $FDS_SVNROOT/Verification/scripts
   echo 'Running SMV verification cases:' >> $FIREBOT_DIR/output/stage5 2>&1
   ./Run_SMV_Cases.sh -q $FIREBOT_QUEUE >> $FIREBOT_DIR/output/stage5 2>&1

   # Wait for all verification cases to end
   wait_verification_cases_long_end
}

check_verification_cases_long()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage5` == "" ]] && \
      [[ `grep ERROR: -rI *` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI *` == "" ]] && \
      [[ `grep -A 20 forrtl -rI *` == "" ]]
   then
      stage5_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage5 > $FIREBOT_DIR/output/stage5_errors
      grep ERROR: -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep 'STOP: Numerical' -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep -A 20 forrtl -rI * >> $FIREBOT_DIR/output/stage5_errors
      
      echo "Errors from Stage 5 - Run verification cases (long run):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage5_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ====================================
#  = Stage 6a - Compile SMV utilities =
#  ====================================

compile_smv_utilities()
{  
   # smokezip:
   cd $FDS_SVNROOT/Utilities/smokezip/intel_linux_64
   echo 'Compiling smokezip:' > $FIREBOT_DIR/output/stage6a 2>&1
   ./make_zip.sh >> $FIREBOT_DIR/output/stage6a 2>&1
   echo "" >> $FIREBOT_DIR/output/stage6a 2>&1
   
   # smokediff:
   cd $FDS_SVNROOT/Utilities/smokediff/intel_linux_64
   echo 'Compiling smokediff:' >> $FIREBOT_DIR/output/stage6a 2>&1
   ./make_diff.sh >> $FIREBOT_DIR/output/stage6a 2>&1
   echo "" >> $FIREBOT_DIR/output/stage6a 2>&1
   
   # background:
   cd $FDS_SVNROOT/Utilities/background/intel_linux_32
   echo 'Compiling background:' >> $FIREBOT_DIR/output/stage6a 2>&1
   ./make_background.sh >> $FIREBOT_DIR/output/stage6a 2>&1
}

check_smv_utilities()
{
   # Check for errors in SMV utilities compilation
   cd $FDS_SVNROOT
   if [ -e "$FDS_SVNROOT/Utilities/smokezip/intel_linux_64/smokezip_linux_64" ]  && \
      [ -e "$FDS_SVNROOT/Utilities/smokediff/intel_linux_64/smokediff_linux_64" ]  && \
      [ -e "$FDS_SVNROOT/Utilities/background/intel_linux_32/background" ]
   then
      stage6a_success=true
   else
      echo "Errors from Stage 6a - Compile SMV utilities:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 6b - Compile SMV DB =
#  ==================================

compile_smv_db()
{
   # Clean and compile SMV DB
   cd $FDS_SVNROOT/SMV/Build/intel_linux_64_db
   ./make_smv.sh &> $FIREBOT_DIR/output/stage6b
}

check_compile_smv_db()
{
   # Check for errors in SMV DB compilation
   cd $FDS_SVNROOT/SMV/Build/intel_linux_64_db
   if [ -e "smokeview_linux_64_db" ]
   then
      stage6b_success=true
   else
      echo "Errors from Stage 6b - Compile SMV DB:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6b >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6b | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 6b warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6b | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ==================================================
#  = Stage 6c - Make SMV pictures (debug mode) =
#  ==================================================

make_smv_pictures_db()
{
   # Run Make SMV Pictures script (debug mode)
   cd $FDS_SVNROOT/Verification/scripts
   ./Make_SMV_Pictures.sh -d 2>&1 | grep -v FreeFontPath &> $FIREBOT_DIR/output/stage6c

}

check_smv_pictures_db()
{
   # Scan and report any errors in make SMV pictures process
   cd $FIREBOT_DIR
   if [[ `grep -B 50 -A 50 "Segmentation" -I $FIREBOT_DIR/output/stage6c` == "" && `grep "*** Error" -I $FIREBOT_DIR/output/stage6c` == "" ]]
   then
      stage6c_success=true
   else
      cp $FIREBOT_DIR/output/stage6c $FIREBOT_DIR/output/stage6c_errors

      echo "Errors from Stage 6c - Make SMV pictures (debug mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6c_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 6d - Compile SMV release =
#  ==================================

compile_smv()
{
   # Clean and compile SMV
   cd $FDS_SVNROOT/SMV/Build/intel_linux_64
   ./make_smv.sh &> $FIREBOT_DIR/output/stage6d
}

check_compile_smv()
{
   # Check for errors in SMV release compilation
   cd $FDS_SVNROOT/SMV/Build/intel_linux_64
   if [ -e "smokeview_linux_64" ]
   then
      stage6d_success=true
   else
      echo "Errors from Stage 6d - Compile SMV release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6d >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6d | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 6d warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6d | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ===============================================
#  = Stage 6e - Make SMV pictures (release mode) =
#  ===============================================

make_smv_pictures()
{
   # Run Make SMV Pictures script (release mode)
   cd $FDS_SVNROOT/Verification/scripts
   ./Make_SMV_Pictures.sh 2>&1 | grep -v FreeFontPath &> $FIREBOT_DIR/output/stage6e
}

check_smv_pictures()
{
   # Scan and report any errors in make SMV pictures process
   cd $FIREBOT_DIR
   if [[ `grep -B 50 -A 50 "Segmentation" -I $FIREBOT_DIR/output/stage6e` == "" && `grep "*** Error" -I $FIREBOT_DIR/output/stage6e` == "" ]]
   then
      stage6e_success=true
   else
      cp $FIREBOT_DIR/output/stage6e  $FIREBOT_DIR/output/stage6e_errors

      echo "Errors from Stage 6e - Make SMV pictures (release mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6e >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 8 - Build FDS-SMV Guides =
#  ==================================

check_guide()
{
   # Scan and report any errors in build process for guides
   cd $FIREBOT_DIR
   if [[ `grep "! LaTeX Error:" -I $1` == "" ]]
   then
      if [ "$FIREBOT_USERNAME" == "smokebot" ]; then
        cp $2 /var/www/html/smokebot/manuals/
      fi
      cp $2 $GUIDE_DIR/.
   else
      echo "Errors from Stage 8 - Build FDS-SMV Guides:" >> $ERROR_LOG
      grep "! LaTeX Error:" -I $1 >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for LaTeX warnings (undefined references or duplicate labels)
   if [[ `grep -E "undefined|multiply defined|multiply-defined" -I ${1}` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 8 warnings:" >> $WARNING_LOG
      grep -E "undefined|multiply defined|multiply-defined" -I $1 >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

make_smv_user_guide()
{
   # Build SMV User Guide
   cd $FDS_SVNROOT/Manuals/SMV_User_Guide
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   bibtex SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_user_guide $FDS_SVNROOT/Manuals/SMV_User_Guide/SMV_User_Guide.pdf
}

make_smv_technical_guide()
{
   # Build SMV Technical Guide
   cd $FDS_SVNROOT/Manuals/SMV_Technical_Reference_Guide
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   bibtex SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_technical_guide $FDS_SVNROOT/Manuals/SMV_Technical_Reference_Guide/SMV_Technical_Reference_Guide.pdf
}

make_smv_verification_guide()
{
   # Build SMV Verification Guide
   cd $FDS_SVNROOT/Manuals/SMV_Verification_Guide
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   bibtex SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_verification_guide $FDS_SVNROOT/Manuals/SMV_Verification_Guide/SMV_Verification_Guide.pdf
}

#  =====================================================
#  = Build status reporting - email and save functions =
#  =====================================================

save_build_status()
{
   cd $FIREBOT_DIR
   # Save status outcome of build to a text file
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     cat "" >> $ERROR_LOG
     cat $WARNING_LOG >> $ERROR_LOG
     echo "Build failure and warnings for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
     cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      echo "Build failure for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      echo "Revision ${SVN_REVISION} has warnings." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $WARNING_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_warnings.txt"

   # No errors or warnings
   else
      echo "Build success! Revision ${SVN_REVISION} passed all build tests." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
   fi
}

email_build_status()
{
   cd $FIREBOT_DIR
   # Check for warnings and errors
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     # Send email with failure message and warnings, body of email contains appropriate log file
     mail -s "smokebot build failure and warnings for Revision ${SVN_REVISION}." $mailTo < $ERROR_LOG > /dev/null

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      # Send email with failure message, body of email contains error log file
      mail -s "smokebot build failure for Revision ${SVN_REVISION}." $mailTo < $ERROR_LOG > /dev/null

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      # Send email with success message, include warnings
      mail -s "smokebot build success, with warnings. Revision ${SVN_REVISION} passed all build tests." $mailTo < $WARNING_LOG > /dev/null

   # No errors or warnings
   else
      # Send empty email with success message
      mail -s "smokebot build success! Revision ${SVN_REVISION} passed all build tests." $mailTo < /dev/null > /dev/null
   fi
}

#  ============================
#  = Primary script execution =
#  ============================

clean_firebot_history

### Stage 0 ###
update_and_compile_cfast

### Stage 1 ###
clean_svn_repo
do_svn_checkout
check_svn_checkout

### Stage 2a ###
# No stage dependencies
compile_fds_db
check_compile_fds_db

### Stage 3 ###
if [[ $stage2a_success ]] ; then
   run_verification_cases_short
   check_verification_cases_short
fi

### Stage 4a ###
if [[ $stage2a_success ]] ; then
   compile_fds
   check_compile_fds
fi

### Stage 5 ###
if [[ $stage4a_success ]] ; then
   run_verification_cases_long
   check_verification_cases_long
fi

### Stage 6a ###
# No stage dependencies
compile_smv_utilities
check_smv_utilities

### Stage 6b ###
# No stage dependencies
compile_smv_db
check_compile_smv_db

### Stage 6c ###
if [[ $stage5_success && $stage6b_success ]] ; then
   make_smv_pictures_db
   check_smv_pictures_db
fi

### Stage 6d ###
if [[ $stage5_success && $stage6b_success ]] ; then
   compile_smv
   check_compile_smv
fi

### Stage 6e ###
if [[ $stage6d_success ]] ; then
   make_smv_pictures
   check_smv_pictures
fi

### Stage 8 ###
if [[ $stage6e_success ]] ; then
   make_smv_user_guide
   make_smv_technical_guide
   make_smv_verification_guide
fi
# No stage dependencies

### Report results ###
set_files_world_readable
save_build_status
email_build_status
