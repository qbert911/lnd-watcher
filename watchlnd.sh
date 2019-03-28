#!/bin/bash
PS1=$
PROMPT_COMMAND=
echo -en "\033]0;LND Watcher\a"
IFS=","

while : ;do
  eval lncli listchannels > rawout.txt
  cat rawout.txt | jq -r '.channels[] | [.remote_pubkey,.capacity,.local_balance,.remote_balance,(.active|tostring),(.initiator|tostring),.commit_fee,.commit_weight,.fee_per_kw] | join("," )' > nodelist.txt
  eval lncli pendingchannels > rawoutp.txt
  cat rawoutp.txt | jq -r '.pending_open_channels[]|[.channel.remote_node_pub,.channel.capacity,.channel.local_balance,.channel.remote_balance,"pendo","true",.commit_fee] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.waiting_close_channels[]|[.channel.remote_node_pub,.channel.capacity,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.pending_closing_channels[]|[.channel.remote_node_pub,.channel.capacity,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  cat rawoutp.txt | jq -r '.pending_force_closing_channels[]|[.channel.remote_node_pub,.channel.capacity,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
  height=`eval lncli getinfo |jq -r '.block_height'`
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
  walletbal=`eval lncli walletbalance |jq -r '.total_balance'`
	unc=`eval lncli walletbalance |jq -r '.unconfirmed_balance'`
  income=`eval lncli feereport | jq -r '.month_fee_sum'`
  limbo=`cat rawoutp.txt | jq -r '.total_limbo_balance'`
  limbot=`cat rawoutp.txt |grep _matur| cut -d":" -f2|tr -d "\n,"`
  fwding=`eval lncli fwdinghistory |jq -c '.forwarding_events[]|[.amt_in,.amt_out,.fee,.fee_msat]'`
  eval lncli getinfo | jq -r '[.identity_pubkey,"","'${outgoingcap}'","'${incomincap}'","--me--"," "," "," "," "]| join("," )' >> nodelist.txt  #add own node to list
  sort nodelist.txt -o nodelist.txt
#----------START--WEB DATA GRABBER---------------------------------------------
  mkdir -p pages;rm -f nodelist-temp.txt pages/webdatanew.txt
  cp nodelist.txt nodelist-temp.txt
  myrecs=$(wc -l nodelist-temp.txt | sed -e 's/ .*//')
  dirty=false
  while read thisID f2 f3 f4 f5; do
      if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +30`" || test -f "mismatch.txt" || ! test -f "pages/webdata.txt" ;then  #freshness check
        dirty=true;fi
  done < nodelist-temp.txt
  if [ "$dirty" = true ];then
    echo "Downloading data for $myrecs nodes: "`date`
    echo -ne "[-----------+-----------+-----------+-----------+----------50%----------+-----------+-----------+-----------+------------]\033[121D"
    barlen=$(( 120 )) #DO MORE
    for (( c=1; c<=$(( $barlen - ( $(( $barlen  / $myrecs )) * $myrecs ) )); c++ )); do echo -ne "=";done        #fill in gap bars segments
    while read thisID f2 f3 f4 f5; do
        if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +30`";then  #freshness check
          eval curl -s https://1ml.com/node/$thisID/channels?order=capacity -o pages/$thisID.html
          for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;54m=\e[0m";done          #draw bar segment
        else
          for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;235m=\e[0m";done          #draw bar segment
        fi #download html
        if eval head -n 200 "pages/$thisID.html" | grep -q 'globe';then
          thisgeodata=`eval head -n 200 pages/$thisID.html|grep -A4 "globe"|pup a,li text{}| tr '\n' ','`
        else thisgeodata=" ,--,--,";fi
          hex=`eval head -n 200 pages/$thisID.html| grep -A1 '<h5>Color</h5>' | pup span text{} | jq -r -R '.[1:7]'`
          r=$(printf '0x%0.2s' "$hex"); g=$(printf '0x%0.2s' ${hex#??}); b=$(printf '0x%0.2s' ${hex#????})  #hex to anso color conversion
        thiscolor=$(echo -e `printf "%03d" "$(((r<75?0:(r-35)/40)*6*6+(g<75?0:(g-35)/40)*6+(b<75?0:(b-35)/40)+16))"`)"m"
        thisnode=`eval head -n 200 pages/$thisID.html|grep     "<h1>Node" |pup h1 text{}| tr -d '()'| sed 's/&lt;//' | sed 's/&gt;//'`
        thiscapacity=`eval head -n 200 pages/$thisID.html|grep -A1 "<h5>Capacity" |pup span text{}`
        thisconnectedcount=`eval head -n 200 pages/$thisID.html|grep -A1 "<h5>Connected Node Count</h5>" |pup span text{}| sed 's/,//'`
        thisage=`eval head -n 300 pages/$thisID.html| grep -A1 '<h5>Age</h5>' | pup span text{}`
        avgchancap=`eval cat pages/$thisID.html| grep -A1 '<h5 class="inline">Capacity</h5>'| pup span text{} | jq -r -R '.[0:-4]' | jq -s add/length`
        thisbiggestchan=`eval cat pages/$thisID.html| grep -A1 '<h5 class="inline">Capacity</h5>'| pup span text{} | jq -r -R '.[0:-4]' | jq -s max`
        eval echo "${thisID},${thisnode:15:80},${thiscapacity:0:-4},${thisconnectedcount},${avgchancap},${thisbiggestchan},${thisage},${thiscolor},${thisgeodata:0:-1}" >> pages/webdatanew.txt  #write line to file
        for (( c=1; c<=$(( ( $barlen  / $myrecs ) - $(( $barlen  / $myrecs / 2 )) )); c++ )); do echo -ne "\e[38;5;99m=\e[0m";done     #draw bar segment
    done < nodelist-temp.txt
    sort pages/webdatanew.txt -o pages/webdata.txt
    rm -f pages/webdatanew.txt mismatch.txt
  fi
#----------END----WEB DATA GRABBER---------------------------------------------
#-------start--combiner--------------------------------------------------------
  rm -f combined.txt     #just in case of program inte
  recs=$((-1))  #so we don't count self
  while read -r thisID capacity balance incoming cstate init cf cw fpk && read -r thatID title thiscapacity thisconnectedcount avgchancap thisbiggestchan age color city state country junk <&3; do
    : $((recs++))
    if [ "$thisID" = "$thatID" ];then
    #--------------processing  	
        if [ "$init"   = "true" ];then balance=$(( $balance + $cf ))
    	elif [ "$init"   = "false" ];then incoming=$(( $incoming + $cf ));fi

    	if [ "$balance"   = "0" ];then balance="";fi
    	if [ "$incoming"  = "0" ];then incoming="";fi

      if [[ -n "$incoming" ]];then incoming="          ${incoming}";incomingA="${incoming:(-9):3}";incomingB="${incoming:(-6):3}";incomingC="${incoming:(-3):3}";incoming="${incomingA// /} ${incomingB// /} ${incomingC// /}";incoming="${incoming/  /}";fi
      incoming="'\e[38;5;232m'...........'\e[0m'${incoming}";incoming="${incoming:0:14}${incoming: -17}"
      if [[ -n "$balance" ]];then abalance="           ${balance}";balanceA="${abalance:(-9):3}";balanceB="${abalance:(-6):3}";balanceC="${abalance:(-3):3}";balance="${balanceA// /} ${balanceB// /} ${balanceC// /}";balance="${balance/  /}";fi
      balance="'\e[38;5;232m'___________'\e[0m'${balance}";balance="${balance:0:14}${balance: -17}"

      title=`eval lncli getnodeinfo ${thisID} |jq -r '.node.alias'| tr -d "<')(>"`
      ipexam=`eval lncli getnodeinfo ${thisID} |jq -r '.node.addresses[].addr'`
      ipstatus="-ip4-";ipcolor="001m"
      if [[ $ipexam == *"n:"* ]];then ipstatus="onion";ipcolor="113m";fi
      if [[ $ipexam == *":"*":"* ]];then ipstatus="mixed";ipcolor="111m";fi
      if [[ $ipexam == *"n:"*"n:"* ]];then ipstatus="onion";ipcolor="113m";fi
      if [[ $ipexam == *":"*":"*":"* ]];then ipstatus="mixed ";ipcolor="111m";fi
      if   [ "$state"   = "" ];then country=$city ;              city=""
    	elif [ "$country" = "" ];then country=$state; state=$city; city="";fi
    #--------------processing 
      OUTPUTME=`eval echo "'\e[38;5;$color'${thisID:0:2}'\e[0m'${thisID:2:7},$balance,$incoming,"$title",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate:0:8},$init,$thisconnectedcount,${thiscapacity:0:6},${avgchancap:0:6},${thisbiggestchan:0:6},$age,${city:0:13},${state:0:5},${country:0:6},$cf"`   #,$cw,$fpk
    else
      OUTPUTME=`eval echo "'\e[38;5;$color'${thisID:0:2}'\e[0m'${thisID:2:7}"`
      echo -e "${OUTPUTME}" >> mismatch.txt
    fi
    echo "${OUTPUTME}" >> combined.txt
  done <nodelist.txt 3<pages/webdata.txt
#---------end--combiner--------------------------------------------------------
    header="[38;5;232m02[0mID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Title,[38;5;001m [0mType,Active,Init,Chans,Cap,AvgChan,Biggest,Age,City,St,Co,Lbs"
    data_table=`cat combined.txt|sort --field-separator=',' -k 7,7 -k 5,5 -k 4`
    echo -e "${header}\n${data_table}" > myout.txt
    OUTPUTME=`cat myout.txt | column -n -ts,`
    incomincap="          ${incomincap}";incomincapA="${incomincap:(-9):3}";incomincapB="${incomincap:(-6):3}";incomincapC="${incomincap:(-3):3}";incomincap="${incomincapA// /} ${incomincapB// /} ${incomincapC// /}";incomincap="${incomincap/  /}"
    walletbal="             ${walletbal}";walletbalA="${walletbal:(-9):3}";walletbalB="${walletbal:(-6):3}";walletbalC="${walletbal:(-3):3}";walletbal="${walletbalA// /} ${walletbalB// /} ${walletbalC// /}";walletbal="${walletbal/  /}"
    outgoingcap="          ${outgoingcap}";outgoingcapA="${outgoingcap:(-9):3}";outgoingcapB="${outgoingcap:(-6):3}";outgoingcapC="${outgoingcap:(-3):3}";outgoingcap="${outgoingcapA// /} ${outgoingcapB// /} ${outgoingcapC// /}";outgoingcap="${outgoingcap/  /}"
  clear
  echo -e "${OUTPUTME}\nChans: \e[38;5;45m${recs}\e[0m ${reco}/${reci}  \e[38;5;157m${outgoingcap} \e[0m \e[38;5;183m ${incomincap}\e[0m \e[38;5;113m ${walletbal}\e[0m in wallet (${unc} unconfirmed) (${limbo} in limbo$limbot) (${unset_balanceo} / ${unset_balancei} unsettled ${unset_times})	Income: \e[38;5;83m${income}\e[0m  ${fwding}"
  rm -f combined.txt myout.txt nodelist.txt nodelist-temp.txt rawout.txt rawoutp.txt
  secsi=$((5));while [ $secsi -gt -1 ]; do echo -ne "$secsi\033[0K\r";sleep 1; : $((secsi--));done   #countdown
done
