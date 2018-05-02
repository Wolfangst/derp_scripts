#!/bin/bash


#NOTE: This version of script should be used as a template only. It has not been tested as it 
#has been re-written by hand to become generic as possible. It will require customisation for
#your environment. To assist with understanding of use case, frequently encountered services
#have been used instead. Processes listed are examples and you should use "ps aux | grep <service>"
#and check_procs -c 1:2 -C <service> to find a service and determine if check_procs will detect it

#Example environment: You have a company that names its servers by country, site, purpose and number,
#eg aussydsat1 for a Satellite server based in Sydney, Australia.
#----------------------------------------------------------------------------------------------------#

#########################################~~PURPOSE~~#########################################
##.....This script is intended to automatically map hostnames to services and generate.....##
##.....                              reports for Nagios                               .....##
#########################################~~._EJP_.~~#########################################


#If there is a particular host or hosts that are used as redundancies and contain the same segment
#used by hosttype (under VARIABLES), exempt them here.

if [[ $(hostname) = *bkp3* ]]; then
    echo "OK: The host process does not require monitoring as this server is a redundancy"
    exit 0
fi

           #############################~~VARIABLES~~#############################

#Store the main command as a string	   
check_procs="/usr/lib64/nagios/plugins/check_procs"

#Location to write a file for Satellite
tempfile="/tmp/tempfile_nagios"

#Determine the type of host. Modify to suit your environment. This follows the above example of
#service specific information being at characters 7-9.
hosttype=$(hostname | cut -c 7-9)

#Cleanup from last time the script was run just in case. Clear the array and remove $tempfile if
#it exists
unset hostprocarray

if [[ -e $tempfile ]]; then
    rm $rmfile
fi

           #############################~~FUNCTIONS~~############################# 
	#~~~~~~~~~~~~~Functions for gathering information on sat server~~~~~~~~~~~~~#

genstats(){

    touch $tempfile || ((echo "Cannot create $tempfile, exiting!" && exit 2))
        for proc in "${hostprocarray[@]}"; do
            #The numbers 1:20 indicate the minimum amount of processes that should be running and the maximum
            $check_procs -c 1:20 -C $proc >> $tempfile
        done

}

        #~~~~~~~~~~~~~~~~~~Functions for extracting reporting data~~~~~~~~~~~~~~~~~#
#Accomodates Sat but was removed from performing this step due to ease of use
#This function is merely a nicety to allow for formatting data

genreport(){

    #Extract the exit status
    exitstatus=$($reader $status | awk '{print $2}' | cut -d : -f1)

    #Grab the data Nagios requires for graphing
    graphdata=$($reader $status | cut -d '|' -f2)

    #Place the number of processes into a variable
    proctotal=$($reader $status | cut -d '=' -f2 | cut -d ';' -f1)

}

        #~~~~~~~~~~~~~Sat tidies data and reports in its own function~~~~~~~~~~~~~# 

reportsat(){
	
    #The purpose of errstat and okstat is to place critical and warning messages at the top, to place the errors
    #of the same type into the same line, seperated by semi-colons and seperate the graph data out for later input
    errstat=$(grep 'CRITICAL\|WARNING' $tempfile | cut -d '|' -f1 | sed '{:q;N;s/\n/;/g;t}')
    okstat=$(grep 'OK' $tempfile | cut -d '|' -f1 | sed 's/PROCS OK://' | sed '{:q;N;s/\n/;/g;t}')
    graphdata=$(cat $tempfile | cut -d '|' -f2)


    #So that okstat informs the user monitoring that the system is thoroughly borked
    if [[ -z $okstat ]]; then
        okstat="0"
    fi


    #Exit codes determined by the contents of $tempfile. Note the proceeding | for graph data is important to Nagios
    if [[ ! -z $errstat ]]; then
        echo "$erstat!!!"
        echo "PROCS OK: $okstat"
        echo " | $graphdata"
        exit 2
    else
        echo $okstat
        exit 0
    fi

}

           ###############################~~MAIN~~################################ 
	#~~~~~~~~~~~~~~~~~Allocate type of process expected on host~~~~~~~~~~~~~~~~~#

#Reminder: Processes and server names here are fake. Refer to the introduction.

#Usage: You can use app="" to assist with determining what a service actually does. In this example you have
#a server-side and a client-side mail service. Args are the command line arguments with which the process is expected
#to run. Multiple processes can be accomodated through arrays, using the sat functions above.

case hosttype in
    bkp)
        hostproc="backupservice.exe" && args="-a hourly"                                       ;;
    cli)
        hostproc="mail"	&& args='-a cli_scope' && app="client-side"                            ;;	
    dns)
        hostproc="bind"                                                                        ;;
    fwd)
        hostproc="firewalld"                                                                   ;;
    ldp)
        hostproc="ldapd"                                                                       ;;
    nag)
        echo "Monitoring of the Nagios server with Nagios is not necessary..."
        exit 0                                                                                 ;;	
    pcs)
        echo "OK: No monitoring of host specific process required"
        exit 0                                                                                 ;;	
    sat)
        hostprocarray=("katello" "foreman" "dhcpd" "bind" "java -a memoryleakingprogram")
        hostproc="sat"                                                                         ;;
    sql)
        hostproc="oracleSQL" && args="-a why_would_you_willingly_use_this"                     ;;	
    svr)    
        hostproc="mail" && args="-a svr_scope" && app="server-side"                            ;;
    tbl)
        hostproc="perl" && args="table-extractor.pl" && app="service to process SQL data"      ;;     
    *)
         echo "Error: Unable to match the host to process. Check configuration"
         exit 1
esac	

        #~~~~~~~~~~~~~~~~~~~~Check the status. Do the thing~~~~~~~~~~~~~~~~~~~~#
#Allow moar instances for cli and svr, for instance. Deviate Sat into its own checks
case $hostproc in
    sat)
        status="$tempfile"
        reader="cat"
        genstats
        reportsat                                                                              ;;
  
    cli|svr)
        status=$($check_procs -c 2:6 -C $hostproc $args)
        reader="echo"
        genreport                                                                              ;;

    *)
        status=$($check_procs -c 1:2 -C $hostproc $args)
        reader="echo"
        genreport
esac

        #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Exit Codes~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#Am I the only one reading it as "Sexitstatus"?
case $exitstatus in
    OK)
       echo "$exitstatus : $hostproc $app is running $proctotal instance(s) | $graphdata" && exit 0    ;;
    *)
       echo "$exitstatus : $hostproc $app is running $proctotal instance(s)!!! | $graphdata" && exit 2 ;;	    
esac

           ###############################~~EOF~~############################### 
