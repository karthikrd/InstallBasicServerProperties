#!/bin/bash

#yet to do
#1.

#done
# 1. In find functions check if variable is already assigned with some value

#VARIABLES
  #Color variables
  CLR="\033[01;32m"
  CLR_RED="\033[1;31m"
  CLR_END="\033[0m"

  #Store the ipaddress and netmask
  ipaddress=""
  netmask=""
  ethName=""
  hwAddr=""
  hostname=""
  OSVersion=""
  OSName=""

#FUNCTIONS

  function dec_line () {
    echo "************ $* **************"
  }

  function printclr () {
    echo -e $CLR"[${USER}][`date`] - ${*}"$CLR_END
  }

  function printerr () {
    echo -e $CLR_RED"[${USER}][`date`] - [ERROR] ${*}"$CLR_END
  }

  function insertToFile () {
    echo "$1" >> $2
  }

  function findIP() {
    case $OSName in  
      Linux)
       case $OSVersion in
         6)
           ipaddress=$(ifconfig| grep 'inet '| grep -v '127.0.0.1'| cut -d: -f2| awk '{ print $1}')
           ;;
         10)
           ipaddress=$(ifconfig| grep 'inet '| grep -v '127.0.0.1'| cut -d: -f2| awk '{ print $2}')
           ;;
       esac
       ;;
     esac
  }

  function findNetmask() {
    case $OSName in
     Linux)
       case $OSVersion in
         6)
           netmask=$(ifconfig | grep 'inet '| grep -v '127.0.0.1' | cut -d: -f4)
           ;;
         10)
           netmask=$(ifconfig | grep 'inet '| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $4}')
           ;;
       esac
     esac
  }

  function findEthName() {
    case $OSName in
     Linux)
       case $OSVersion in
         6)
           ethName=$(ifconfig | head -1 | awk '{print $1}')
           ;;
         10)
           ethName=$(ifconfig | head -1 | awk '{print $1}' | rev | cut -c 2- | rev)
           ;;
       esac
     esac
  }

  function findHwAddr() {
    case $OSName in
     Linux)
       case $OSVersion in
         6)
           hwAddr=$(ifconfig | grep HWaddr | awk '{ print $5 }')
           ;;
         10)
           hwAddr=$(ifconfig | grep ether | awk '{ print $2 }')
           ;;
       esac
     esac
  }

  function findOSName() {
    OSName=$(uname)
  }

  function findOSVersion() {
    tempOSVersion=$(uname -r)
   
    IFS='.'
    arr=($tempOSVersion)
    OSVersion=${arr[1]}
  }

  function findHostname() {
    IFS='.'
    temp_ipaddr=""

    #Change the ipaddress of the format a.b.c.d to a-b-c-d
    for num in $ipaddress
    do
     temp_ipaddr="$temp_ipaddr-$num"
    done

    #Remove the '-' in the begining of temp_addr
    temp_ipaddr=$(echo $temp_ipaddr | cut -c 2-)

    hostname="node-${temp_ipaddr}.cw.com"
  }

  function checkAndInstallPackages () {
   package="$1"
   
    if p=$(rpm -qa | grep "$package") ; then
      printclr "$package already installed"
    else
      #Install package
      yum --verbose install "$package" -y &> /dev/null
      if q=$(rpm -qa | grep "$package") ; then
        printclr "$package installed successfully"
      else
        printerr "$package installation failed"
      fi
    fi
  }

  function restartService () {
    printclr "Restarting $1"
    service $1 restart &> /dev/null
    printclr "Restarted $1 successfully"
  }

  function setStaticIp () {
    staticIPFile="/etc/sysconfig/network-scripts/ifcfg-$ethName"
    #staticIPFile="staticIPFile1"
    temp_File="staticIPFile"

    insertToFile "DEVICE=$ethName" $temp_File
    insertToFile "NAME=$ethName" $temp_File
    insertToFile "BOOTPROTO=static" $temp_File
    insertToFile "IPV6INIT=no" $temp_File
    insertToFile "ONBOOT=\"yes\"" $temp_File
    insertToFile "TYPE=\"Ethernet\"" $temp_File
    insertToFile "IPADDR=$ipaddress" $temp_File
    insertToFile "NETMASK=$netmask" $temp_File
    insertToFile "GATEWAY=192.168.1.1" $temp_File
    insertToFile "DNS1=192.168.1.1" $temp_File

    case $OSName in 
     Linux)
       case $OSVersion in
         6)
           insertToFile "MTU=\"1500\"" $temp_File
           ;;
         10)
           insertToFile "HWADDR=$hwAddr" $temp_File
           ;;
         *)
           printerr "Cannot change to staticIP on this OS $OSName with version $OSVersion"
       esac
       cp $temp_File $staticIPFile
       printclr "Static IP is set"
       ;;
     *) 
       printerr "Cannot change to staticIP on this OS $OSName"
    esac

    #Delete the temporary file
    rm -rf $temp_File &> /dev/null
  }

  function setHostname () {

    #Check the OS Name and version and then change the hostname accordingly
    if [ "$OSName" == "Linux" ] ; then
      if [ "$OSVersion" == "6" ] ; then
        OLD_HOSTNAME="$( hostname )"
        NEW_HOSTNAME="$hostname"
        hostname "$NEW_HOSTNAME"
        sed -i "s/HOSTNAME=.*/HOSTNAME=$NEW_HOSTNAME/g" /etc/sysconfig/network
        if [ -n "$( grep "$OLD_HOSTNAME" /etc/hosts )" ]; then
          sed -i "s/$OLD_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
        else
          echo -e "$( hostname -I | awk '{ print $1 }' )\t$NEW_HOSTNAME" >> /etc/hosts
        fi        
        #hostname $hostname &> /dev/null
        printclr "Changed hostname to $hostname"
      elif [ "$OSVersion" == "10" ] ; then
        hostnamectl --static set-hostname "${hostname}"
        #hostname $hostname &> /dev/null
        printclr "Changed hostname to $hostname"
      else
        printerr "Cannot change hostname to $hostname in $OSName with version $OSVersion"
      fi
    else
      printerr "Cannot change hostname to $hostname in $OSName"
    fi
  }

  function updateHostsFile () {
    hostsFile="/etc/hosts"
    
    #Delete hostname if already present
    sed -i "/$ipaddress/d" $hostsFile

    #Insert the new hostname
    insertToFile "$ipaddress $hostname" $hostsFile
  }

  function setSwapMemory () {
    if [ "$1" = false ] ; then
      sysctl -w vm.swappiness=0 &> /dev/null
      swapoff -a &> /dev/null
      echo "vm.swappiness=0" >> /etc/sysctl.conf
      printclr "Turned off the swap"

      sysctl -w vm.max_map_count=131072 &> /dev/null
      echo "vm.max_map_count = 131072" >> /etc/sysctl.conf
      printclr "Increased the max map count 131072"
    fi
  }

  function installJava () {
   
    printclr "Downloading Java 1.7.0_51 ... "
    #Install and set the java 1.7.0_51 version
    wget --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/7u51-b13/jdk-7u51-linux-x64.rpm" -O /opt/jdk-7-linux-x64.rpm &> /dev/null
    printclr "Download completed"
 
    printclr "Installing Java 1.7.0_51"
    rpm -Uh /opt/jdk-7-linux-x64.rpm &> /dev/null
    alternatives --install /usr/bin/java java /usr/java/jdk1.7.0_51/jre/bin/java 20000 &> /dev/null
    alternatives --set java /usr/java/jdk1.7.0_51/jre/bin/java &> /dev/null
    printclr "Installed successfully"
  }

  function installPackages() {
    checkAndInstallPackages "rsync"
    checkAndInstallPackages "net-tools"
    checkAndInstallPackages "wget"
  }

  function checkAndAssignDefault () {
    #Find OSName and OSVersion initially based on which the below are found
    findOSName
    findOSVersion

    if [ ! "$ipaddress" ] ; then
      findIP
    fi

    if [ ! "$netmask" ] ; then
      findNetmask
    fi

    if [ ! "$hostname" ] ; then
      findHostname
    fi

    findEthName
    findHwAddr

  }

  function installNTP () {
    #SERVICECHECK="ntp.x86_64"
    SERVICE="ntp"

    #Check if ntp is already running
    #Install ntp only if it is not running
    if p=$(rpm -qa | grep "$SERVICE-") ; then
      printclr "$SERVICE already installed"
    else
      #Install package
      yum --verbose install "$SERVICE" -y &> /dev/null
      if q=$(rpm -qa | grep "$SERVICE") ; then
        printclr "$SERVICE installed successfully"
      else
        printerr "$SERVICE installation failed"
      fi
    fi


    if P=$(pgrep $SERVICE) ; then
      printclr "$SERVICE is running ... "
    else
      #Sync with a particular server
      #You can obtain list of servers from /etc/ntp.conf
      ntpdate 0.centos.pool.ntp.org &> /dev/null

      #Start ntp server
      service ntpd start &> /dev/null
      if [ $? -eq 0 ]; then
        printclr "$SERVICE started sucessfully"

        #Make sure ntp starts as soon as the system starts
        chkconfig ntpd on &> /dev/null
      else
        printerr "$SERVICE failed to start"
      fi
    fi
  }

#LOGIC

  dec_line "Welcome to the HADOOP pre-requisites installation process"
  while getopts i:n:h: opt; do
    case $opt in
    i)
      ipaddress=$OPTARG
      ;;
    n)
      netmask=$OPTARG
      ;;
    h)
      hostname=$OPTARG
      ;;
    *)
      echo "Invalid option -$opt"
      exit 1
    esac
  done

  #Check and find the default options if not given
  installPackages
  checkAndAssignDefault  

  #Install and assign the static ip and hostname
  dec_line "Static IP"
  setStaticIp

  dec_line "Hostname"
  setHostname
  updateHostsFile

  dec_line "Swap"
  setSwapMemory "false"

  dec_line "JAVA"
  echo "Do you want to install Java 1.7.0_51 (y/n)"
  read choice junk
  if [ $choice = "y" ] ; then
  installJava
  fi

  dec_line "NTP" 
  installNTP

  dec_line "Restart Network"
  restartService "network"

  dec_line "Summary"
  printclr "IP: $ipaddress"
  printclr "netmask: $netmask"
  printclr "HwAddr: $hwAddr"
  printclr "OSName: $OSName"
  printclr "OSVersion: $OSVersion"
  printclr "Hostname: $hostname"

