#面向对象常用命令规范： 
#   全局常量"以_分割的全大写"  全局变量"以_分割且无单独动词"的大写驼峰式  局部变量"小写驼峰式"
#   pub级类方法Func_  pro/pri级类方法_Func_  pub级实例方法[fF]unc  pro/pri级实例方法_[fF]unc
#   pub级类变量Var_   pro/pri级类变量_Var_   pub级实例变量Var   pro/pri级实例变量_Var
#   函数命名："以_分割且有单独动词"的驼峰式   ，动词大写开头的pubMethod一般为关键字函数kc/kt
#   变量命名: "小写驼峰式"代表真正的变量， 某变量的变量名在前面插入_
#   

#  [LIBDBG -Comdata 1 xxx] =>   信息固定打印在$_Comname日志中，
#			LIBDBG(dvCOM,stdout)置1时，信息同时打印在stdout中
#  [LIBDBG -f 1 xxx] => 信息固定打印在sum、$_Comname两个日志中，及stdout中
#  [ff f]  => 打印出LIBDBG中的信息

package require itclx
if {[itcl::find classes COM]!=""} {return "already exists Class COM"}
source lib/tclcommon.tcl
source lib/kManage.tcl

if {![info exists __tclcommon__]} {
  proc LIBDBG_set args {}
  proc LIBDBG_logOpen args {}
  proc LIBERR {args} {uplevel 1 $args}
  set Debug 1
  proc LIBDBG {args} {
    if {$::Debug} {puts $args}
  }
  set LIBDBG(fNameLs) ""
}
;

set COM_This ""   ;# 当前活跃对象$this，便于对$::COM_This.f和$::COM_This._Comdata的灵活操作
#trace add variable COM_This write f_trace_varWrite
proc CLASS-COM {} {}
;# 该类用于命令行方式控制目标，由Comid、Comname(主机名/IP地址/串口名)来区分各个通道
class COM {   ;# 加载dvCOM.tcl时会生成一个默认对象::com0用于
  public variable _Comid   {}
  public variable _Comname {}
  public variable _Comdata  {}                  ;# COM通道中的【完整数据信息】
  public variable _ComSerCfg  {9600,8,n,1,N}                ;# 串口处理
  public variable _chantype {}    ;#连接方式
  
  public method This        ;# 通过改变::COM_This使f函数的作用对象切换
  public method _init
  public variable _IfInitSuccess 0
  public method _link
  public method _login
  public method _reset
  
  public proc f             ;# 因该方法极为常用，为方便使用未使用"f_"这样的规范命名
  #public method fCmd
  public method Init
  public method adb_root
  public method _rx
  public method _tx
  public method _write_Com
  public method _read_Com                  ;# 从COM通道中读<一次临时信息>
  public method _collect_Comdata           ;# 从COM通道中收集【完整数据信息】

  public variable _IfTrimComdata 1      ;# 是否需修整数据
  public variable _TrimComdataMap {
    [0m {}    [01;32m {}  [01;34m {}  [34;42m {}
    [m]0; {} ]0; {}    ~ {}        [30;42m {}
    [1;34m {}  [1;36m {}  [0m {}
  }
  public method _trim_Comdata            ;# 需修整数据时，根据_TrimDataMap修整
  
  public variable _Counter 0           ;# 计数器，每次f下命令时会增1
  public variable _DstInit {}          ;# 记录控制目标的初始化信息
  public variable _Dft                 ;# 默认的控制属性
  public variable _MaxReadMax 1000     ;# 最大的maxRead值为1000，约100秒
  constructor {{dftSet ""}} {
    if {$::COM_This=="<IfInitClass_COM=0>"} {return {}}
    set ::COM_This $this
    array set _Dft {
      LoginRemind "Login"  PasswordRemind "Password" LoginLs "admin admin" MaxRead 5
      ComCfg {-blocking 0 -buffering line -buffersize 409600 -translation binary -encoding utf-8}
      ReadGap 100 ReadEnd "> # ]"
      FastRead {"Unknown" "Error" "Missing"
      "login*:" "password:" "Login:" "Password:" "Welcome to.*" "invalid command"
      "Command Groups:" "Available Commands:" "other to continue!" "Description:"
      }
    }
    array set _Dft $dftSet    ;# 注:  "-encoding"选项需在"-translation"选项之后才能保证一定生效
    set _Dft(RegReadEnd) [format "%s%s%s" {^.*(} [join $_Dft(ReadEnd) |] {)( *|\n*)$}]
    set _Dft(RegFastRead) [format "%s%s%s" {(?n).*(} [join $_Dft(FastRead) |] {) *}]
    puts "COM new obj {$this}"
  }
  destructor {catch {close $_Comid}}
}
;
classEnd COM

# 切换整个继承树的::*_This，在kc/kt中会自动调用。主要
# 常用于①WEB体系中的WEB_This/COM_This ②IPC体系中的COM_This
# 
proc -This {} {}
itcl::body COM::This {} {
  foreach className [$this info heritage] {
    set gloablThis "${className}_This"  ;# exam:    ::COM_This
    uplevel #0 "if \[info exists $gloablThis] {set $gloablThis $this}" 
  }
  set ::COM_This $this
}
;

proc -_init {} {}
itcl::body COM::_init {dst {loginLs "<undefined>"} {linkTryTimes 1}}  {
	LIBDBG ""
	set chanName [lindex $dst 0]
  #LIBDBG -log接口需要一个logFile来记录log信息
	if {$chanName ni $::LIBDBG(fNameLs)} {LIBERR LIBDBG_logOpen $chanName}
  
  _reset
	if {![_link $dst $loginLs $linkTryTimes]} {
    set _IfInitSuccess 0
    return $::ERR
  }
  #记录该通道名对应的初始化信息，主要用于fc_tx中的自动修复通道机制
  set _DstInit [list $dst $loginLs]
  set _IfInitSuccess 1
  #chan configure $_Comid {*}$_Dft(ComCfg)
  #fconfigure $_Comid -mode $ComRate,n,8,1  
  lassign $dst _Comname chanType
  set _chantype $chanType
  if {$chanType == "ssh" || $chanType == "serial"|| $chanType == "adb"} {
  fconfigure $_Comid -blocking 0  
  fconfigure $_Comid -buffering none
  fconfigure $_Comid -buffersize 409600
  fconfigure $_Comid -translation binary
  fconfigure $_Comid -encoding utf-8
  fileevent $_Comid readable "" 
  } else {
   chan configure $_Comid {*}$_Dft(ComCfg)
  }

  if {$chanType != "adb"} {LIBERR $this _login $loginLs}
  if {$chanType == "adb" && [adb_root] !=1} {return $::ERR}
  set ::COM_This $this
	return $::SUC
}
;
proc -Init {} {}
itcl::body COM::Init {{dst "192.168.21.11 ssh"} {loginLs "root tendatest"} {chanCfg ""}} {
  lassign $dst _Comname chanType
  if {$chanType != "adb"} {
	f_KillProcess -name adb.exe
  }

  set initRes [_init $dst $loginLs $chanCfg]
  LIBDBG "initRes=$initRes"
  
  if {$initRes != $::ERR && $chanType != "adb" } {f "q"}
  
  
  
  
  return $initRes
}
;

#adb通道进入root会话框
proc -adb_root {} {}
itcl::body COM::adb_root {} {
  set _rv 0
  for {set _i 0} {$_i<3} {incr _i} {
      f "su"
	  puts [._Comdata]
	  if {[regexp {\#} [._Comdata]] == 1} {
	    return 1 
	  }
	}
  return $_rv
}
;

;# _linkPre
proc -_reset {} {}
itcl::body COM::_reset {}  {  ;# 不能使用f，只能用底层的catch {_tx ...}，否则会死循环
	catch {close $_Comid}
}

;# _linkPost
#proc COM-::_firtSend {}  {  ;# 不能使用f，只能用底层的catch {_tx ...}，否则会死循环
#	catch {_tx q}
#}
;
;# 修剪Data中的杂糅编码（主要是颜色导致的）
proc -_trim_ComData {} {}
itcl::body COM::_trim_Comdata {data} {
  if {$_IfTrimComdata=="0"} {return ""}
  return [string map $_TrimComdataMap $data]
}
;
;#[辅助级] 正式连接通道
proc -_link {} {}
itcl::body COM::_link {dst loginLs {tryTimes 3}} {
  set _rv 0
	lassign $dst _Comname chanType
  lassign $loginLs login password
  LIBDBG -f 1 [list $dst $loginLs $tryTimes]
  set ipMode 1
	if {![f_ip_reg $_Comname]} {     #exam: dst=={plink.exe -ssh 10.0.0.10}
    #set toSet [list open "|$dst" r+]
    if {$chanType == "serial"} {
    set toSet [list open "|plink.exe -$chanType $_Comname -sercfg $_ComSerCfg" r+]
    } elseif {$chanType == "adb"} {  #ex: set fid [open "|plink.exe -ssh 10.0.0.10" r+]
		set toSet [list open "|adb.exe -s $_Comname shell" r+]
        set _rv 1
    } else {set toSet [list open "|$dst" r+]}
    set ipMode 0
    set _rv 1
  } elseif {[string is integer $chanType]} {
    if {$chanType==""} {set chanType 23}
    set toSet [list socket $_Comname $chanType]
    set _rv 1
  } elseif {$chanType == "ssh"} {  #ex: set fid [open "|plink.exe -ssh 10.0.0.10" r+]
		set toSet [list open "|plink.exe -$chanType $_Comname -l $login -pw $password" r+]
    set _rv 1
   } else {
    LIBDBG "无效的_link方式={$dst}"
    return 0
  }
	LIBDBG "set $this._Comid \[eval {$toSet}]"
  for {set i 1} {$i<=1} {incr i} {
    if {$ipMode && [km SYS_Ping DIp=$_Comname MaxSuc=1 MaxErr=3 Debug=1 Interval=0]!=$::TSPASS} {
      LIBDBG "km SYS_ping $_Comname 失败"
    } elseif [catch {set _Comid [eval $toSet]} err] {
      LIBDBG "打开通道时候异常. err={$err}"
    } else {
      LIBDBG "打开新的$_Comname 通道：$_Comid"
      set _rv 1
    }
    #after $_Dft(ReadGap)
  }

 #if {$_rv != 0} { 
  #for {set _i_ 0} {$_i_<30} {incr _i_} {
     # if {[catch {set comdatas [.$this._read_Com]} err]} {
     # LIBDBG "Link函数尝试等待通道打通，但error={$err}"
     # } elseif {$comdatas!="" && [string first # $comdatas] != -1} {
     # puts "comdatas$comdatas" 
     # LIBDBG "Link函数打通ssh通道~"
     # return 1
     # }
    # after 1000
     #puts "$_i_ [_read_Com]"
   #}
 #} 
  
  
  return $_rv
}
;
;# 登陆通道
proc -_login {} {}
itcl::body COM::_login {{loginLs "<undefined>"}} {
  if {$loginLs==""} {set loginLs $_Dft(LoginLs)}
  if {$loginLs=="<undefined>"} {return 1}
  lassign $loginLs login password
  
	LIBDBG " loginLs={$loginLs}"
	
  set _Comdata ""
  set _ret 1
	_write_Com "$login"
  #puts "[_read_Com]"
  #after $_Dft(ReadGap)
  if {[set iread [_read_Com]]!=""} {LIBDBG -Comdata 1 [append _Comdata "\n$iread"]}
  for {set i 0} {$i<4} {incr i} {
    if {[_rx "$_Dft(LoginRemind)" nocase]} {
      _write_Com "$login"
    } elseif [_rx "$_Dft(PasswordRemind)" nocase] {
      _write_Com "$password"
    } else {
      break
    }
    #after $_Dft(ReadGap)
    if {[set iread [_read_Com]]!=""} {LIBDBG -Comdata 1 [append _Comdata "\n$iread"]}
  }
   if {$_chantype == "serial" && [regexp {~ #} $_Comdata] != 1} {
    set _ret 0
   }
   # if {$_chantype == "adb" && [regexp {\$} $_Comdata] != 1} {
    # set _ret 0
   # }
	return $_ret
}
;
proc -_write_Com {} {}
itcl::body COM::_write_Com {cmd {noTrace 0}} {
	set _Dft(Counter) [format 0x%04x [incr _Dft(Counter)]]
	
  if {!$noTrace} {
    uplevel 1 [list LIBDBG -f 1 "[string repeat { } 6]$_Comname<$_Dft(Counter)>: {$cmd}"]
    #uplevel 1 [list LIBDBG -f 1 "  $_Comname<$_Dft(Counter)>"]
  }
	puts $_Comid $cmd
  flush $_Comid
}
;
# 纯粹的读一次通道临时数据tempData
# 一般情况下tempData∈_Comdata只有当"Init或f -nocheck"时，_read_Com的值才会直接写入_Comdata
proc -_read_Com {} {}
itcl::body COM::_read_Com {} {
  update
  after 200
  return [_trim_Comdata [read $_Comid]]
}
;
# 收集完整的通道数据_Comdata，以下3种情况下会完成收集
# ①已收集到FastRead关键信息 ②尝试收集次数达到MaxRead
# ③已收集信息的末行，能匹配ReadEnd，且末行长度>命令长度
proc -_collect_Comdata {} {}
itcl::body COM::_collect_Comdata {{maxRead 5}} {
  set _Comdata ""
	for {set times 1} {$times<$maxRead} {incr times} {
    if {$times%20==0} {puts "  .COM._collect_Comdata: times=$times"}
    set tempData [_read_Com]
    #puts -nonewline "      itime={$times}"
    if {$tempData!=""} {
      if {[string index $_Comdata end]!="\n"} {append _Comdata "\n"}
      append _Comdata "$tempData"
      set charEnd [string trimright [lindex [split [string trim $tempData \n] \n] end]]
      set matchFast [regexp $_Dft(RegFastRead) $tempData]
      set matchEnd  [regexp $_Dft(RegReadEnd) $charEnd]
      #puts "\n  \[regexp {$_Dft(RegReadEnd)} {$charEnd}] = $matchEnd"
      #if {$matchFast || ($matchEnd && ([llength $charEnd]>$cmdLen))} {break}
      if {$matchFast || $matchEnd} {break}
    }
    after $_Dft(ReadGap)
	}
  #append _Comdata [_read_Com]      ;# 最后再保险收集一次
  set _Comdata [string trim $_Comdata]
}
;
;# 发送命令后，期望接收到的末行数据（通过匹配符判断是否匹配上） 
proc -_rx {} {}
itcl::body COM::_rx {match {nocase ""}} {
	set dataEnd [lindex [split $_Comdata "\n"] end]
  if {$nocase!=""} {
    return [string match -nocase "*$match*" $dataEnd]
  } else {
    return [string match "*$match*" $dataEnd]
  }
}
;
# COM com1; com1 _init ...; f "1"  ;# => puts cmd "1" to com1
# COM com2; com2 _init ...; f "2"  ;# => puts cmd "2" to com2
# f -com1 "3 x y" ;f "4"            ;# => puts cmd "3 x y" to com1; puts cmd "4" to com1
# f "-com2 5\t"                   ;# => puts cmd "-com2 5\t" to com1   
# proc -f {} {}
# itcl::body COM::f {cmd1 {cmd2 "<undefined>"}} {
  # LIBDBG ""
  # if {$cmd2 != "<undefined>"} {
    # set cmdSend $cmd2
    # set cmdOpt  $cmd1
  # } else {
    # set cmdSend $cmd1
    # set cmdOpt  ""
  # }
  
  # if {[set sId [lsearch -regexp $cmdOpt {^-[^=]+$}]] > -1} {
    # set comThis [lindex $cmdOpt $sId]
  # } else {
    # if {![uplevel 1 {info exists this}]} {
      # LIBDBG "!\[uplevel 1 {info exists this}"
      # set comThis $::COM_This
    # } else {
      # set comThis [uplevel 1 {set this}]
      # LIBDBG "\[uplevel 1 {set this}]=$comThis"
    # }
  # }
  # if {[itcl::find objects [::itclx::_nmspFull $comThis] -isa ::COM]!=""} {set ::COM_This $comThis}
  # if {$cmd2 != "<undefined>"} {
    # set opt [f_getOpt $cmd1 -*]
    # set obj [::itclx::_nmspFull $opt]
    # if {[itcl::find objects $obj -isa ::COM]!=""} {set ::COM_This $obj}
  # }
  # return [f_3op "{[$::COM_This f $cmdOpt $cmdSend]}==1" ?$::TSPASS: $::TSFAIL]
# }
# ;

# 带容错的命令发送方式
set COM::fExpl(f) {
#语法: f ?cmdOpt? cmdSend
#说明: 发命令操作，主要用于操作命令行。通过::COM_This机制来区分当前obj，
#      在kc/kt中会调用[$obj This]来切换整个继承树的::*_This。
#      发命令然后收集结果(定时去读通道，直到读到自定义结束符或超出最大读次数)
#参数: cmdSend  下发命令
#      cmdOpt  选项
#      -maxRead=*  收集结果的最大读次数(约0.1s每次)，最大只生效至_MaxReadMax
#      -wait       tx前等待waitTime秒
#      -waitRead   rx前等待waitRead秒
#      -expl=*     (少用)注释(rx跟踪打印时的前缀)
#      -nocheck    (少用)不检查结束符，此时下发命令后会硬性等0.3s后读通道并返回
#      -noTrace    (少用)tx时不跟踪打印
#      -noPrint    (少用)rx时不跟踪打印
#exam: f "-maxRead=10 -waitRead=1" xxx
}
proc -f {} {}
itcl::body COM::f {cmd1 {cmd2 "<undefined>"}} {
  puts "cmd1=$cmd1,$cmd2"
  if {$cmd1 == "-?"} {return [string trim [set ::COM::fExpl(f)]]}
  LIBDBG ""
  if {$cmd2 != "<undefined>"} {
    set cmdSend $cmd2
    set cmdOpt  $cmd1
  } else {
    set cmdSend $cmd1
    set cmdOpt  ""
  }
  puts "cmd2=$cmd1,$cmd2"
  set obj $::COM_This
  #set retryTimes [f_getOpt $cmdOpt -retryTimes=* 1]
  #if {$retryTimes==""} {set retryTimes 1}
  
  
  #set ::COM_This $this    ;# 【类方法中不能直接调用对象方法、对象变量，故必须在f下再封装一层fCmd】
  #if {$_IfInitSuccess!=1} {
  #  return [puts "  {$this}未初始化登陆成功，跳过本次命令行下发{$cmd}"]
  #}
  #先清除通道内残余信息，以免影响该次命令发送
  if {[catch {set comdata [$obj _read_Com]} err]} {
    LIBDBG -f 1 "尝试先清除通道内残余信息，但error={$err}"
  } elseif {$comdata!=""} {
    LIBDBG -f 1 "\n[string repeat - 80]\n\"$comdata\"\n[string repeat - 80]"
  }
	;
  # if {$_chantype == "serial"} {
    # $obj _write_Com "\n"
    # if {[catch {set comdata [$obj _read_Com]} err]} {
    # LIBDBG -f 1 "尝试先清除通道内残余信息，但error={$err}"
    # } elseif {$comdata!="" &&} {
    # LIBDBG -f 1 "\n[string repeat - 80]\n\"$comdata\"\n[string repeat - 80]"
    # }
  # }
  
  # 若发命令不报错，则立即返回。  #注：取消重试机制 yjw:2015/05/05
  
  puts "fcmd=$cmdSend"
  
  
	if {![catch {$obj _tx $cmdOpt $cmdSend} err_tx]} {
    if {$_chantype == "adb" ||$_chantype == "ssh" || $_chantype == ""} {
    return $::TSPASS
    } elseif {[regexp {~ #} $_Comdata] == 1} { 
     return $::TSPASS
    }
    # if {[$obj cget -_Comdata]!=""} {return $::TSPASS}
    # LIBDBG -f 1 " [$obj cget -_Comname]通道读取值为{}，重试第(1/1)次"
    # if {![catch {$obj _tx $cmdOpt $cmdSend} err_tx2]} {return $::TSPASS}
    # append err_tx "\n  err_tx2={$err_tx2}"
  }
  
  LIBDBG -f 1 " 【[$obj cget -_Comname]通道异常】，尝试修复后重下命令 ，err_tx={$err_tx}"
    lassign [$obj cget -_DstInit] dstName dstLoginLs
  
  if {$_chantype == "serial"} {
    set _i 0
    while {$_i < 30} {
      if {[$obj _login $dstLoginLs]==1} {
          LIBDBG -f 1 " 【重新登录成功，尝试重复发送命令】"
          $obj _tx $cmdOpt "\n"
          if [catch {$obj _tx $cmdOpt $cmdSend} err_tx] {
          LIBDBG -f 1 " 【重新登录后，下命令仍失败】"
          return $::TSFAIL
          } else {
          return $::TSPASS
        }
      }
      LIBDBG -f 1 " 【重新登录失败】"
      incr _i
      after 500
     }
    }
  if {[$obj _init $dstName $dstLoginLs 1] != $::SUC} {
    LIBDBG -Comdata 1 " 【[$obj cget -_Comname]修复通道  失败!!!】"
    return $::TSFAIL
  }
	
  if [catch {$obj _tx $cmdOpt $cmdSend} err_tx] {
    LIBDBG -f 1 " 【[$obj cget -_Comname]尝试修复后，下命令仍失败】"
    return $::TSFAIL
  } else {
	#if {$_chantype == "adb" && [adb_root] !=1} {return $::TSFAIL}
    return $::TSPASS
  }
}
;
;# 发送命令 cmd1可形如"{-maxRead=2 -readGap=100 -nocheck -noPrint} ls"
proc -_tx {} {}
itcl::body COM::_tx {cmd1 {cmd2 "<undefined>"}} {
	LIBDBG ""
  if {$cmd2 != "<undefined>"} {
    set cmdSend $cmd2
    set cmdOpt  $cmd1
  } else {
    set cmdSend $cmd1
    set cmdOpt  ""
  }

  set nocheck [f_3op "{[f_getOpt $cmdOpt -nocheck]}!={}" ?1: 0]  ;# 不检查结束符
  #set readGap [f_getOpt $cmdOpt -readGap=* 100]
  set maxRead [f_getOpt $cmdOpt -maxRead=* $_Dft(MaxRead)]
  if {$maxRead > $_MaxReadMax} {set maxRead $_MaxReadMax}
  
  set noTrace [f_3op "{[f_getOpt $cmdOpt -noTrace]}!={}" ?1: 0]  ;# tx时不跟踪
  set noPrint [f_3op "{[f_getOpt $cmdOpt -noPrint]}!={}" ?1: 0]  ;# rx时不打印
  set expl [f_getOpt $cmdOpt -expl=* ""]    ;# 注释

  set waitTime [f_getOpt $cmdOpt -wait=* 0.0]
  set waitRead [f_getOpt $cmdOpt -waitRead=* 0.0]
  #if {![string is double $waitTime]} {set waitTime 0.0}
  #if {![string is double $waitTime]} {set waitRead 0.0}
  
  LIBDBG "maxRead=$maxRead nocheck=$nocheck waitRead=$waitRead waitTime=$waitTime"
  
  if {$waitTime>0.3} {puts "       ... 本次下发命令前wait ${waitTime}s"}
  after [format "%.0f" [expr 1000*$waitTime]]
	_write_Com $cmdSend $noTrace
	if {$nocheck} {
		after 300 ; flush $_Comid ; LIBDBG -Comdata 1 [set _Comdata [_read_Com]]
    return 1
	}
	#
  
  if {$waitRead>0.3} {puts "       ... 本次读取前wait ${waitRead}s"}
  after [format "%.0f" [expr 1000*$waitRead]]
  _collect_Comdata $maxRead
  if {!$noPrint && $_Comdata!=""} {     ;# 
    if {$expl != ""} {set dataPre "{$expl} : "} else {set dataPre ""}
    LIBDBG -Comdata 1 "[string repeat { } 6]$_Comname<Read>  : $dataPre{$_Comdata}"
  }
	if {$_Comdata==""} {return 0} else {return 1}
}
;


proc COM_END {} {
}
namespace eval COM {
  namespace export f
}
namespace import COM::*
puts "Success for load dvCOM.tcl"
  

#用plink.exe打开的进程，关闭管道甚至关闭tcl解释器后该进程仍存在，此处加载时先杀1次
f_KillProcess -name plink.exe


