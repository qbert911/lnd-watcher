#!/bin/bash
PS1=$;PROMPT_COMMAND=;echo -en "\033]0;LND Watcher\a"
IFS=","
updatetime=$((7))
while : ;do
#----------START--LND RPC POLLING----------------------------------------------
  height=`eval lncli getinfo |jq -r '.block_height'`
  walletbal=`eval lncli walletbalance |jq -r '.total_balance'`
  unconfirmed=`eval lncli walletbalance |jq -r '.unconfirmed_balance'`
  income=`eval lncli fwdinghistory --start_time 5000 --end_time 50000000000000000|jq -r '[.forwarding_events[]|(.fee_msat|tonumber)]|add'`
  fwding=`eval lncli fwdinghistory |jq -c '.forwarding_events[]|.amt_in+"("+.fee_msat+") "'|tr -d '\n"'`
  
  eval lncli listchannels > rawout.txt
  cat rawout.txt | jq -r '.channels[] |select(.private==false)| [.remote_pubkey,.local_balance,.remote_balance,(.active|tostring),(.initiator|tostring),.commit_fee,.chan_id] | join("," )' > nodelist.txt
  reco=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) | "1"|tonumber]|add'`
  reci=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | "1"|tonumber]|add'`
  unset_balanceo=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) |.unsettled_balance|tonumber]|add'`
  unset_balancei=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | .unsettled_balance|tonumber]|add'`
  unset_times=`cat rawout.txt | jq -r -s '[.[].channels[].pending_htlcs[].expiration_height|select(length > 0)-'${height}'|tostring]|join(",")'`
  mybalance=`cat rawout.txt | jq -s '[.[].channels[].local_balance|tonumber]|add'`
  cap_balance=`cat rawout.txt | jq -s '[.[].channels[].remote_balance|tonumber]|add'`
  commitfees=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) | .commit_fee|tonumber]|add'`
  ocommitfees=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | .commit_fee|tonumber]|add'`
  outgoingcap=$(( ${mybalance} + ${commitfees} ))
  incomincap=$(( ${cap_balance} + ${ocommitfees} )) 
  
  eval lncli pendingchannels > rawoutp.txt
  cat rawoutp.txt | jq -r '.pending_open_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pendo","true",.commit_fee] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.waiting_close_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.pending_closing_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.pending_force_closing_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  limbo=`cat rawoutp.txt | jq -r '.total_limbo_balance'`
  limbot=`cat rawoutp.txt |grep _matur| cut -d":" -f2|tr -d "\n,"`
  
  eval lncli getinfo | jq -r '[.identity_pubkey,"'${outgoingcap}'","'${incomincap}'","--me--"," "," "]| join("," )' >> nodelist.txt  #add own node to list
  
  sort nodelist.txt -o nodelist.txt
  displaywidth=`tput cols`
  if   [ "$displaywidth" -gt 174 ]; then dispsize="A";colorda="007m";colordb="007m";colordc="007m";colordd="007m";colorde="001m";updatetimed=$updatetime
  elif [ "$displaywidth" -gt 134 ]; then dispsize="B";colorda="007m";colordb="007m";colordc="007m";colordd="001m";colorde="007m";updatetimed=$updatetime
  elif [ "$displaywidth" -gt 104 ]; then dispsize="C";colorda="007m";colordb="007m";colordc="001m";colordd="007m";colorde="007m";updatetimed=$updatetime
  elif [ "$displaywidth" -gt 79  ]; then dispsize="D";colorda="007m";colordb="001m";colordc="007m";colordd="007m";colorde="007m";updatetimed=$updatetime
  else                                   dispsize="E";colorda="001m";colordb="007m";colordc="007m";colordd="007m";colorde="007m";updatetimed=$((5));fi
  walletbal="             ${walletbal}";walletbalA="${walletbal:(-9):3}";walletbalB="${walletbal:(-6):3}";walletbalC="${walletbal:(-3):3}";walletbal="${walletbalA// /} ${walletbalB// /} ${walletbalC// /}";walletbal="${walletbal/  /}"
#----------START--WEB DATA GRABBER---------------------------------------------
  myrecs=$(wc -l nodelist.txt | sed -e 's/ .*//')
  savedrecs=$(wc -l pages/webdata.txt | sed -e 's/ .*//')
  dirty=false
  while read thisID unused; do
    if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +30`" || ! test -f "pages/webdata.txt" ;then dirty=true;break    #freshness check
    elif [ "$myrecs" != "$savedrecs" ];then dirty=true;break;fi
  done < nodelist.txt
  if [ "$dirty" = true ];then
    mkdir -p pages;rm -f pages/webdata.txt
    echo "Downloading data about $myrecs nodes from 1ml.com : "`date`
    barlen=$(( $displaywidth )) 
    for (( c=1; c<=$(( $barlen - ( $(( $barlen  / $myrecs )) * $myrecs ) )); c++ )); do echo -ne "=";done        #fill in gap bars segments
    while read thisID f2 f3 f4 f5; do
        if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +27`";then  #freshness check
          eval curl -s https://1ml.com/node/$thisID/channels?order=capacity -o pages/$thisID.html   #download html
          for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;54m=\e[0m";done    #draw bar segment
        else for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;235m=\e[0m";done;fi   #draw bar segment
        if eval head -n 200 "pages/$thisID.html" | grep -q 'globe';then
          thisgeodata=`eval head -n 200 pages/$thisID.html|grep -A4 "globe"|pup a,li text{}| tr '\n' ','`
        else thisgeodata=" , , ";fi
          hex=`eval head -n 200 pages/$thisID.html| grep -A1 '<h5>Color</h5>' | pup span text{} | jq -r -R '.[1:7]'`
          r=$(printf '0x%0.2s' "$hex"); g=$(printf '0x%0.2s' ${hex#??}); b=$(printf '0x%0.2s' ${hex#????})  #hex to ansi color conversion
        thiscolor=$(echo -e `printf "%03d" "$(((r<75?0:(r-35)/40)*6*6+(g<75?0:(g-35)/40)*6+(b<75?0:(b-35)/40)+16))"`)"m"
        thiscapacity=`eval head -n 200 pages/$thisID.html|grep -A1 "<h5>Capacity" |pup span text{}`
        thisconnectedcount=`eval head -n 200 pages/$thisID.html|grep -A1 "<h5>Connected Node Count</h5>" |pup span text{}| sed 's/,//'`
        thisage=`eval head -n 300 pages/$thisID.html| grep -A1 '<h5>Age</h5>' | pup span text{}`
        avgchancap=`eval cat pages/$thisID.html| grep -A1 '<h5 class="inline">Capacity</h5>'| pup span text{} | jq -r -R '.[0:-4]' | jq -s add/length`
        thisbiggestchan=`eval cat pages/$thisID.html| grep -A1 '<h5 class="inline">Capacity</h5>'| pup span text{} | jq -r -R '.[0:-4]' | jq -s max`
        
        title=`eval lncli getnodeinfo ${thisID} |jq -r '.node.alias'| tr -d "<')(>&|," |tr -d '"´'|tr -dc [:print:][:cntrl:]`    #remove problem characters from alias
        ipexam=`eval lncli getnodeinfo ${thisID} |jq -r '.node.addresses[].addr'`
        ipstatus="-ip4-";ipcolor="089m"
        if [[ $ipexam == *"n:"* ]];then        ipstatus="onion";ipcolor="113m";fi
        if [[ $ipexam == *":"*":"* ]];then     ipstatus="mixed";ipcolor="111m";fi
        if [[ $ipexam == *"n:"*"n:"* ]];then   ipstatus="onion";ipcolor="113m";fi
        if [[ $ipexam == *":"*":"*":"* ]];then ipstatus="mixed";ipcolor="111m";fi
        for (( c=1; c<=$(( ( $barlen  / $myrecs ) - $(( $barlen  / $myrecs / 2 )) )); c++ )); do echo -ne "\e[38;5;99m=\e[0m";done     #draw bar segment
        eval echo "${thisID},${title},${ipstatus},${ipcolor},${thiscapacity:0:-4},${thisconnectedcount},${avgchancap},${thisbiggestchan},${thisage},${thiscolor},${thisgeodata:0:-1}" >> pages/webdata.txt  #write line to file
    done < nodelist.txt
  fi
#----------START--TABLE BUILDER------------------------------------------------
  rm -f combined.txt     #just in case of program interruption
  while read -r thisID balance incoming cstate init cf chanid && read -r thatID title ipstatus ipcolor thiscapacity thisconnectedcount avgchancap thisbiggestchan age color city state country junk <&3; do
    #--------------processing
    if [ "${cstate:0:1}" = "f" ];then cstate=$(echo "$(( ( $(date +%s) - $(lncli getnodeinfo ${thisID} |jq -r '.node.last_update') ) / 3600 ))hrs" );fi
    if   [ "$state"   = "" ];then country=$city ;              city=""
    elif [ "$country" = "" ];then country=$state; state=$city; city="";fi
    if   [ "$init"   = "true" ];then balance=$(( $balance + $cf ))
  	elif [ "$init"   = "false" ];then incoming=$(( $incoming + $cf ));fi
  	if [ "$balance"   = "0" ];then balance="";fi
  	if [ "$incoming"  = "0" ];then incoming="";fi
    if [[ -n "$incoming" ]];then incoming="          ${incoming}";incomingA="${incoming:(-9):3}";incomingB="${incoming:(-6):3}";incomingC="${incoming:(-3):3}";incoming="${incomingA// /} ${incomingB// /} ${incomingC// /}";incoming="${incoming/  /}";fi
    if [[ -n "$balance" ]];then abalance="           ${balance}";balanceA="${abalance:(-9):3}";balanceB="${abalance:(-6):3}";balanceC="${abalance:(-3):3}";balance="${balanceA// /} ${balanceB// /} ${balanceC// /}";balance="${balance/  /}";fi
    incoming="'\e[38;5;232m'_____________'\e[0m'${incoming}";incoming="${incoming:0:14}${incoming: -19}"
    balance="'\e[38;5;232m'_____________'\e[0m'${balance}";balance="${balance:0:14}${balance: -19}"
    #--------------display table size configurator
    if   [ "$dispsize" = "A" ];then
      OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:2},$balance,$incoming,"$title",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate:0:8},$init,$thisconnectedcount,${thiscapacity:0:6},${avgchancap:0:6},${thisbiggestchan:0:6},$age,${city:0:10},${state:0:5},${country:0:7}"`
      header="[38;5;232m02[0m Channel   ID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,Active,Init,Nodes,Capac.,AvgChan,Biggest,Age,City,State,Country"
    elif [ "$dispsize" = "B" ];then
      OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:2},$balance,$incoming,"${title:0:19}",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate:0:8},$init,$thisconnectedcount,${thiscapacity:0:6},${avgchancap:0:6},${thisbiggestchan:0:6},$age"`
      header="[38;5;232m02[0m Channel   ID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,Active,Init,Nodes,Capac.,AvgChan,Biggest,Age"
    elif [ "$dispsize" = "C" ];then
      OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:2},$balance,$incoming,"${title:0:19}",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate:0:8},$init,$thisconnectedcount,${thiscapacity:0:6}"`
      header="[38;5;232m02[0m Channel   ID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,Active,Init,Nodes,Capac."
    elif [ "$dispsize" = "D" ];then
      OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:(-3)},$balance,$incoming,"${title:0:18}",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate:0:8},$init"`
      header="[38;5;232m02[0mID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,Active,Init"
    else
      OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:(-3)},$balance,$incoming,"${title:0:5}",'\e[38;5;$ipcolor' ${ipstatus:0:1}'\e[0m',${cstate:0:1},${init:0:1}"`
      header="[38;5;232m02[0mID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mT,A,I"
    fi
    echo "${OUTPUTME}" >> combined.txt
  done <nodelist.txt 3<pages/webdata.txt
#----------START--DISPLAY & WAIT---------------------------------------------
  echo -e "${header}\n`cat combined.txt|sort --field-separator=',' -k 7,7 -k 5,5 -k 4`"  | column -n -ts, > myout.txt  #main data table
  clear;  echo -e `cat myout.txt` #helps with screen refresh lag?
  echo -e "  (${unconfirmed} unconf) (${limbo} in limbo$limbot) (${unset_balanceo} / ${unset_balancei} unsettled ${unset_times}) Recent fwds: ${fwding}"
  echo -e "In wallet: \e[38;5;45m${walletbal}\e[0m    Income: \e[38;5;83m${income}\e[0m msat   Channels: \e[38;5;99m$(( $myrecs - 1))\e[0m (${reco}/${reci})"
  rm -f combined.txt myout.txt nodelist.txt rawout.txt rawoutp.txt
  secsi=$updatetimed;while [ $secsi -gt -1 ]; do echo -ne " Columns~"`tput cols`" [\e[38;5;${colorda}50\e[38;5;$colordb 80\e[38;5;$colordc 105\e[38;5;$colordd 135\e[0m and\e[38;5;$colorde 175\e[0m] "
  for (( c=1; c<=$(( $updatetimed - $secsi )); c++ )); do echo -ne " ";done ;  for (( c=1; c<=$(( $secsi )); c++ )); do echo -ne "»";done ;echo -ne " \e[38;5;173m$secsi\e[0m "
  for (( c=1; c<=$(( $secsi )); c++ )); do echo -ne "«";done ;echo -en "\033[0K\r\e[?25l"; if  [ $secsi -ne 0 ];then sleep 1;fi ; : $((secsi--));done   #countdown
done
