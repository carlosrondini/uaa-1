#!/bin/bash -eu

################################################################################
# script:     lib.sh
# brief:      JPaaS Operation basic interface lib 平台运维基础库
# func:       F1 - 定义一些常用的全局常量，如果有必要则在自己的脚本中重新赋值
#             F2 - 定义运维维护所需的日志函数
#             F3 - 定义运维维护所需的报警函数
#             F4 - 定义进程pid检查和杀死的函数
#             F5 - 定义模块全量备份：建议在执行 stop 接口的时候添加
#             F6 - 定义模块启动的依赖检查项，根据需要进行组合检查
#             F7 - 定义运维的全部接口，如果有必要则进行重新定义
# todos:      (1) 功能进行文件拆分，小而美
#             (2) 功能进行丰富化，完备性                  to be continue ...
# history:    2014/03/14 revised edition
################################################################################

################################################################################
# Part 1 : Define common used global consts, reassigned if needed
#          定义一些常用的全局常量，如果有必要则在自己的脚本中重新赋值
################################################################################

# 服务名称，需要在运维接口脚本中重新定义，比如 nats
: ${PRO_NAME:=$(basename ${0%%_control})}

# 服务路径，需要在运维接口脚本中重新定义，比如 /home/work/nats
: ${PRO_HOME:="$(pwd)/$(dirname $0)"}

# 运维接口程序的相关路径，默认定义为 ${PRO_HOME}/opbin 路径，建议无需重新定义
# 比如 /home/work/nats/opbin
: ${BIN_PATH:="$PRO_HOME/opbin/bin"}
: ${CONF_PATH:="$PRO_HOME/opbin/conf"}
: ${DATA_PATH:="$PRO_HOME/opbin/data"}
: ${LOG_PATH:="$PRO_HOME/opbin/log"}

################################################################################
# Part 2 : Define logging utility for operation
#          定义运维维护所需的日志函数
################################################################################

# 日志颜色：fatal-red  warning-yellow  notice-green
: ${COLOR_ORIGIN:="\033[0m"}
: ${COLOR_GREEN:="\033[1;32;40m"}
: ${COLOR_YELLOW:="\033[1;33;40m"}
: ${COLOR_PURPLE="\033[1;35;40m"}
: ${COLOR_RED:="\033[1;31;40m"}

# 日志级别: fatal >=1  info >=2  warning >=3  notice >=4，建议不做改动
: ${LOGGER_LEVEL:="4"}

# 日志输出文件，默认定义为 ${PRO_HOME}/opbin/control.log，建议不做改动
: ${LOGGER_PATH:="$LOG_PATH"}
: ${LOGGER_FILE:="control.log"}

# 日志追踪脚本，一般需要在 control 脚本中被重新赋值，如 SCRIPT=$0
: ${SCIRPT:="$0"}

# 定义公用 logger 函数
function logger() {
    cur_level=$1
    cur_type=$2
    cur_color=$3
    shift 3
    cur_msg=$*

    [[ ${LOGGER_LEVEL} -lt ${cur_level} ]] && return 0

    mkdir -p ${LOGGER_PATH}

    pre_fix="${cur_color}[${cur_type}][$(date +%F)][$(date +%T)][${SCIRPT}]"
    pos_fix="${COLOR_ORIGIN}"
    echo -e "${pre_fix} ${cur_msg} ${pos_fix}" | tee -a ${LOGGER_PATH}/${LOGGER_FILE} >&2
}

# 定义 notice，不退出 
function notice() {
    logger 4 "NOTICE" ${COLOR_GREEN} $*
}

# 定义 warning，不退出
function warning() {
    logger 3 "WARNING" ${COLOR_YELLOW} $*
}

# 定义 info，不退出
function info() {
    logger 2 "WARNING" ${COLOR_PURPLE} $*
}

# 定义 fatal，强制异常退出
function fatal() {
    logger 1 "FATAL" ${COLOR_RED} $*
    exit 1
}

################################################################################
# Part 3 : Define alert utility for operation
#          定义运维维护所需的报警函数
################################################################################

# 默认邮件发送命令
: ${MAIL_CMD:="/bin/mail"}

# 默认短信发送命令
: ${GSM_CMD:="/bin"}

# 默认报警邮件接收人：默认为空
: ${MAILLIST:=""}

# 默认报警短信接收人：默认为空
: ${MOBILELIST:=""}

# 发邮件函数：echo text | sendmail title
function sendmail() {
    $MAIL_CMD -s "$* - from $(hostname)" $MAILLIST
}

# 发短信的函数，用法为sendgsm "短信内容"
function sendgsm() {
    for mobile in $MOBILELIST
    do
        $GSM_CMD $mobile@"$* - from $(hostname)"
    done
}

# 报警函数，包装了fatal, sendmail, sendgsm
function alert() {
    # 发邮件
    echo "$*" | sendmail "$*"
    # 发短信
    sendgsm "$*"
}

################################################################################
# Part 4 : Define proc pid handling utility
#          定义进程 pid 检查和杀死的函数
################################################################################

# 进程监管状态变量定义
: ${STATE_SUCCEED:=0}
: ${STATE_FAILED:=1}
: ${STATE_UNEXPECT:=2}
: ${PID_TIMEOUT:=20}

# 托管监控名称，需要被重新定义
: ${SUPERVISE_MODULE_NAME:="supervise.${PRO_NAME}"}

# 进程对应 PID 记录的文件，为全局变量
: ${PID_FILE:="none"}

# 生成进程对应的 PID 记录文件：保存于 PID_FILE 全局变量
function gen_pidfile() {
    local config_file=$1

    [[ -f ${config_file} && `grep "pid" ${config_file}` ]] && {
        PID_FILE=`grep "pid" ${config_file} | awk -F':' '{print $2}'`
        notice "Getting pid_file : ${PID_FILE} succeed!"
        return 0
    }

    fatal "Getting pid_file unexpected, please do check ${CONFIG_FILE} !"
}

# 杀死特定进程，需要传入进程号
function wait_pid() {
    local cur_pid=$1

    local cur_timeout=${PID_TIMEOUT}
    [[ -z "${PID_TIMEOUT}" || "${PID_TIMEOUT}" -lt 0 ]] && {
        cur_timeout=10
    }

    [[ -z "${cur_pid}" ]] && {
        fatal " The pid [${cur_pid}] to be killed does not exist!"
        return ${STATE_UNEXPECT}
    }

    [[ -e "/proc/${cur_pid}" ]] && {
        kill ${cur_pid}

        start_point=${SECONDS}
        while [[ -e "/proc/${cur_pid}" ]]; do
            duration=$((SECONDS-start_point))
            [[ "${duration}" -gt "${cur_timeout}" ]] && {
                warning "The pid [${cur_pid}] is to be killed with -9 !"
                kill -9 ${cur_pid}
                sleep 1
                break
            }
        done

        [[ -e "/proc/${cur_pid}" ]] && {
            fatal "Process still exists after kill -9 !"
            return ${STATE_FAILED}
        } || {
            notice "The pid [${cur_pid}] has been killed succeed!"
            return ${STATE_SUCCEED}
        }
    } || {
        warning "The process is not running!"
        return ${STATE_UNEXPECT}
    }

    return ${STATE_UNEXPECT}
}

# 杀死特定进程，需要传入进程号记录文件
function wait_pidfile() {
    local cur_pidfile=$1

    [[ -f "${cur_pidfile}" ]] && {
        cur_pid=$(head -1 "${cur_pidfile}")
        wait_pid ${cur_pid}
    } || {
        warning "${cur_pidfile} not exist, maybe process is not running!"
        return ${STATE_UNEXPECT}
    }
}

# 检查进程状态，需要传入进程号
function do_pidstatus() {
    local cur_pidfile=$1

    [[ ! -f "${cur_pidfile}" ]] && {
        warning "${cur_pidfile} is missing, please check!"
        return ${STATE_FAILED}
    }

    local cur_pid=`head -1 ${cur_pidfile}`
    [[ -n "${cur_pid}" && -e "/proc/${cur_pid}" && -n "$(pidof ${SUPERVISE_MODULE_NAME})" ]] && {
        notice "pid status checking OK!"
        return ${STATE_SUCCEED}
    } || {
        warning "pid status checking ERROR!"
        return ${STATE_FAILED}
    }
}

# 检查进程状态，需要传入进程号记录文件
function check_pidstatus() {
    local cur_pidfile=$1

    count=0
    while [[ $count -lt ${PID_TIMEOUT} ]]; do
        sleep 1
        count=`expr $count + 1`

        do_pidstatus ${cur_pidfile} && {
            notice "${PRO_NAME} running succeed"
            return ${STATE_SUCCEED}
        }
    done

    fatal "${PRO_NAME} fail to start: ${cur_pidfile} checking failed!"
    return ${STATE_FAILED}
}

################################################################################
# Part 5 : Define module stop backup interface
#          定义模块全量备份：建议在执行 stop 接口的时候添加
################################################################################

# 备份至 /home/work/opdir/backup/`date -d "0 day ago " +%Y%m%d`
function backup_self() {
    local backup_base_path="/home/work/opdir/backup/`date -d "0 day ago " +%Y%m%d`"
    local pro_base_path=`dirname ${PRO_HOME}`

    mkdir -p ${backup_base_path} && {
        [[ -f "${backup_base_path}/${PRO_NAME}.tar.gz" ]] && {
            warning "${backup_base_path}/${PRO_NAME}.tar.gz exists, skip backup ~"
        } || {
            cd ${pro_base_path} && {
                tar zcf ${PRO_NAME}.tar.gz ${PRO_NAME}/ --exclude=*log --exclude=rootfs --exclude=buildpacks \
                --exclude=tmp  && {
                    mv ${PRO_NAME}.tar.gz ${backup_base_path} && {
                        notice "${PRO_NAME} backup to ${backup_base_path} succeed ~"
                    } || {
                        fatal "mv ${PRO_NAME} backup to ${backup_base_path} failed !"
                    }
                } || {
                    fatal "tar ${PRO_NAME} backup to ${backup_base_path} failed !"
                }
            }
        }
    } || {
        fatal "mkdir ${PRO_NAME} backup to ${backup_base_path} failed !"
    }
}

################################################################################
# Part 6 : Define module start checking depends items, combine while starting
#          定义模块启动的依赖检查项，根据需要进行组合检查
################################################################################

# 检查操作账号: root
function check_root() {
    [[ `whoami` == "root" ]] && {
        notice "using the root account, check okay!"
    } || {
        fatal "using `whoami` account, check error!"
    }
}

# 检查操作账号: work
function check_work() {
    [[ `whoami` == "work" ]] && {
        notice "using the work account, check okay!"
    } || {
        fatal "using `whoami` account, check error!"
    }
}

# 检查操作系统: CentOS
function check_os() {
    [[ `cat /etc/redhat-release` =~ "CentOS release 6.3" ]] && {
        notice "CentOS release 6.3, check okay!"
    } || {
        fatal "OS check error!"
    }
}

# 检查系统内核: >= 2.6.32
function check_kernel() {
    [[ `uname -r` =~ "2.6.32" ]] && {
        notice "Kernel is : `uname -r`, check okay!"
    } || {
        fatal "Kernel is : `uname -r`, check error!"
    }
}

# 安装依赖运行时：公用部分
function yum_common() {
    check_root

    yum -y install bzr
    yum -y install libxslt-devel.x86_64
    yum -y install glibc-static
}

# 安装依赖运行时：虚拟部分
function yum_vm() {
    adduser work

    yum --enablerepo=c6-m clean metadata
    yum -y install gcc gcc-c++ gdb autoconf automake make openssh-clients
    yum -y install curl curl-devel zlib-devel openssl-devel perl cpio expat-devel gettext-devel
    yum -y install glibc-static readline-devel
    yum -y install git openssl-devel zlib-devel gcc gcc-c++ make autoconf readline-devel
    yum -y install libyaml libyaml-devel quota glibc-static libxslt libxslt-devel libxml2 libxml2-devel
    yum -y install mysql-devel postgresql-devel sqlite-devel zip unzip
}

# 安装依赖的组件包地址: 需要后续改进，暂时这么处理 TODO
PKG_ENV="ftp://e"

# 安装依赖的组件包函数
function install_opbin_pkg() {
    pkg=$1
    base_dir=/home/work/opbin

    [[ -n ${pkg} ]] || fatal "pkg is unkown, please do check"

    mkdir -p ${base_dir} && chown -R work:work ${base_dir}      # !!!

    rm -rf ${DATA_PATH}/${pkg}.tgz ${DATA_PATH}/${pkg}

    wget -q ${PKG_ENV}/${pkg}.tgz -P ${DATA_PATH} && {
        notice "downloading ${pkg} into ${DATA_PATH} succeed"
    } || {
        warning "downloading ${pkg} into ${DATA_PATH} failed"
    }

    cd ${DATA_PATH} && {
        tar zxf ${DATA_PATH}/${pkg}.tgz
        chown -R work:work ${DATA_PATH}/${pkg}                  # !!!
        cd - > /dev/null
    }

    mv ${DATA_PATH}/${pkg} ${base_dir} && {
        notice "mv ${DATA_PATH}/${pkg} to  ${base_dir} suceed"
    } || {
        warning "mv ${DATA_PATH}/${pkg} to  ${base_dir} failed"
    }

    export PATH=${base_dir}/${pkg}/bin:$PATH
}

# 安装依赖的 ruby
function install_ruby() {
    base_dir=/home/work/opbin
    pkg_name=ruby-1.9.3-p448
    check_pkg=${base_dir}/${pkg_name}
    [[ `${check_pkg}/bin/ruby -v` =~ "1.9.3p448" ]] && {
        notice "${check_pkg} exists, check okay"
    } || {
        warning "No ${check_pkg}, try install it"
        install_opbin_pkg ${pkg_name}
    }

    [[ `${check_pkg}/bin/ruby -v` =~ "1.9.3p448" ]] || {
        fatal "install ${pkg_name} failed"
    }
}

# 安装依赖的 go
function install_go() {
    base_dir=/home/work/opbin
    pkg_name=go
    check_pkg=${base_dir}/${pkg_name}
    [[ `${check_pkg}/bin/go version` ]] && {
        notice "${check_pkg} exists, check okay"
    }|| {
        warning "No ${check_pkg}, try install it"
        install_opbin_pkg ${pkg_name}
    }

    [[ `${check_pkg}/bin/go version` ]] || {
        fatal "install ${pkg_name} failed"
    }
}

# 安装依赖的 python
function install_python {
    base_dir=/home/work/opbin
    pkg_name=python-2.7.2
    check_pkg=${base_dir}/${pkg_name}
    [[ -e "${check_pkg}/bin/python" ]] && {
        notice "${check_pkg} exists, check okay"
    }|| {
        warning "No ${check_pkg}, try install it"
        install_opbin_pkg ${pkg_name}
    }

    [[ -e "${check_pkg}/bin/python" ]] || {
        fatal "install ${pkg_name} failed"
    }
}

# 安装依赖的 mysql
function install_mysql() {
    base_dir=/home/work/opbin
    pkg_name=mysql
    ps -ef | grep mysql[d] | grep /home/work/opbin && {
        notice "mysql is on, check okay"
    } || {
        warning "No mysql detected, try install it"
        install_opbin_pkg ${pkg_name}

        [[ -f /etc/my.cnf ]] && {
            warning "/etc/my.cnf detected, backup to /etc/my.cnf.bak"
            mv /etc/my.cnf /etc/my.cnf.bak
        }

        cd ${base_dir}/${pkg_name} && {
            [[ `whoami` == "root" ]] && {                # !!!
                su work ./bin/mysql_install_db
                su work ./mysql_control.sh start
            } || {
                ./bin/mysql_install_db
                ./mysql_control.sh start
            }

            cd -
        }

        while true
        do
            [[ "2" == "`ps -ef | grep mysql[d] | wc -l`" ]] && break
            sleep 1
        done
        sleep 2

        ps -ef | grep mysql[d] && {
            cd ${base_dir}/${pkg_name} && {
                ./bin/mysql -u root <<-HD_INIT
create database cc_ng;
grant all privileges on cc_ng.* to work_cc@'%' identified by 'work_cc' with grant option;
grant all privileges on cc_ng.* to work_cc@localhost identified by 'work_cc' with grant option;
flush privileges;
create database uaa_ng;
grant all privileges on uaa_ng.* to 'work_uaa'@'%' identified by 'work_uaa' with grant option;
flush privileges;
HD_INIT
          } || fatal "entering into ${base_dir}/${pkg_name} failed"
        } || {
            fatal "install mysql failed"
        }
    }
}

# 设定内核网络参数
function set_net_params
{
    [[ `/sbin/sysctl -p 2>/dev/null | grep "$2"` ]] && {
        notice "$1 has bee setted okay"
        return 0
    }

    # $1 for name; $2 for the whole setting
    [[ `grep "$1"  /etc/sysctl.conf` ]] && {
        sed -i "s/.*$1.*/$2/" /etc/sysctl.conf
    } || {
        echo "$2" >> /etc/sysctl.conf
    }

    [[ `/sbin/sysctl -p 2>/dev/null | grep "$2"` ]] && {
        notice "set $1 successfully"
    } || {
        fatal "fail to set $1"
        return 1
    }
}

# 网络参数初始化
function network_initial() {
    check_root

    modprobe ip_conntrack
    [[ `cat /etc/rc.local | grep "modprobe ip_conntrack"` ]] && {
        notice "modprobe ip_conntrack okay"
    } || {
        notice "modprobe ip_conntrack >> /etc/rc.local"
        echo "modprobe ip_conntrack" >> /etc/rc.local
    }

    [[ -e /etc/sysctl.conf ]] && {
        notice "/etc/sysctl.conf exists, okay"
    } || {
        fatal "/etc/sysctl.conf doesn't exist"
        return 1
    }

    #ip_local_port_range
    set_net_params "net.ipv4.ip_local_port_range" "net.ipv4.ip_local_port_range = 10000  61000"

    #nf_conntrack
    ##net.ipv4.netfilter.ip_conntrack_max
    set_net_params "net.ipv4.netfilter.ip_conntrack_max" "net.ipv4.netfilter.ip_conntrack_max = 655350"
    ##net.ipv4.netfilter.ip_conntrack_tcp_timeout_established
    set_net_params "net.ipv4.netfilter.ip_conntrack_tcp_timeout_established" "net.ipv4.netfilter.ip_conntrack_tcp_timeout_established = 1200"

    #TCP_FIN_TIMEOUT
    set_net_params "net.ipv4.tcp_fin_timeout" "net.ipv4.tcp_fin_timeout = 5"
    #TCP_TW_RECYCLE
    set_net_params "net.ipv4.tcp_tw_recycle" "net.ipv4.tcp_tw_recycle = 1"
    #TCP_TW_REUSE
    set_net_params "net.ipv4.tcp_tw_reuse" "net.ipv4.tcp_tw_reuse = 1"

    notice "echo 1 >  /proc/sys/net/ipv4/ip_forward"
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

# 进行 mfs 挂载
function mfs_mount() {
    local LOCALDIR="/home/work/appdata/mfs"
    local SERVERDIR="/sdc_paas_ng/jpaas"

    [[ $(df | grep "${LOCALDIR}") ]] && {
        notice "${LOCALDIR} already mounted, okay"
        exit 0
    }

    check_root

    [[ -d ${LOCALDIR} ]] && {
        notice "${LOCALDIR} already exist."
    } || {
        su work -c "mkdir -vp ${LOCALDIR}"
    }

    rm -rf /tmp/mfs_client_deploy_3.sh

    bash /tmp/mfs_client_deploy_3.sh ${LOCALDIR} ${SERVERDIR}
    rm /tmp/mfs_client_deploy_3.sh

    [[ $(df | grep "${LOCALDIR}") ]] && {
        notice "MFS mounted on ${LOCALDIR} succeed"
    } || {
        warning "MFS mounted on ${LOCALDIR} failed"
    }
}

# 设定 suduers
function make_sudoers() {
    check_root

    notice "allow work do something ~"
    # allow work do something
    sed -i '/work.*ALL=(ALL).*ALL/d' /etc/sudoers
    sed -i '/TRUSTCMD/d' /etc/sudoers
    sed -i 's/root.*ALL=(ALL).*ALL/root    ALL=(ALL)       ALL\nCmnd_Alias      TRUSTCMD = \/bin\/mv, \/bin\/kill, \/usr\/bin\/rsync, \/bin\/rm, \/bin\/chmod\nwork    ALL=(ALL)      NOPASSW
D:TRUSTCMD/g' /etc/sudoers
}

# 替换 127.0.0.1 或者 localhost 为本机真实 ip [local_route]
function change_ip() {
    local config_file=$1

    [[ ! -f ${config_file} ]] && {
        fatal "${config_file} not exist, please do check!"
    }

    change_ip_list=(
        "localhost"
        "127.0.0.1"
    )
    feature_str="local_route"
    real_ip=`hostname -i`

    for ((i=0; i<${#change_ip_list[@]}; i++))
    do
        cur_ip=${change_ip_list[$i]}
        [[ `grep "${feature_str}" ${config_file} | grep -v "grep" | grep "${cur_ip}"` ]] && {
            sed -i -e "s/${cur_ip}/${real_ip}/g" ${config_file} && {
                notice "do change ${cur_ip} to ${real_ip} succeed ~"
            } || {
                fatal "do change ${cur_ip} to ${real_ip} failed ~"
            }
        } || notice "no need do change ip for ${cur_ip}"
    done
}

# 安装依赖的 gem 包
function gem_init_local()
{
    cd ${PRO_HOME} && bundle install --local > /dev/null && {
        notice "bundle install --local succeed ~"
    } || {
        fatal "bundle install --local failed !"
    }
}

################################################################################
# Part 7 : Define main operation interfaces, redefined if needed
#          定义运维的全部接口，如果有必要则进行重新定义
################################################################################

# 启动模块的重试时间（1s重试一次）
: ${START_WAIT_TIME:=10}
# 停止模块的重试时间（1s重试一次）
: ${STOP_WAIT_TIME:=10}

# 全局定的常量在这边被重新赋值 !!!
function refresh_consts() {
    # script name
    SCIRPT=$0

    # module config file
    CONFIG_FILE="${PRO_HOME}/config/${PRO_NAME}.yml"

    # supervise
    SUPERVISE="${PRO_HOME}/opbin/bin/supervise"

    # module bin path
    MODULE_BIN_PATH="${PRO_HOME}/bin"

    # supervise deamon
    SUPERVISE_DEAMON_NAME="daemon.${PRO_NAME}"

    # supervise module
    SUPERVISE_MODULE_NAME="supervise.${PRO_NAME}"
}

# 异常抓取函数
function err_trap() {
    fatal "[LINE:$1] command or function exited with status $?"
}

trap "err_trap $LINENO" ERR

# [统一执行][**Main entery**] 入口：action $*
function action() {

    # $1为动作，$2为动作的参数(暂时不支持)
    : ${func:=${1:-'other'}}
    shift || true
    : ${para:=${@:-''}}

    info "Do check: your choice action is \"${func}\" ~"

    # 执行动作
    case "$func" in
        start) start ;;
        stop) stop ;;
        restart|re) stop && sleep 2 && start ;;
        status|st) ck_status ;;
        *) usage ;;
    esac
}

# [重载接口][user_usage] 帮助：如果有需要则重载该函数
function user_usage() {
    return 0
}

# [实现接口][usage] 帮助：内部调用 user_usage
function usage() {
    cat <<-HD_USAGE

${PRO_NAME} 运维接口

[用法]
$0 action [para]

[接口列表]
start:       启动程序, 重载接口为 ck_start，请重新定义
stop:        停止程序, 重载接口为 ck_stop，请重新定义
restart/re:  重启程序, 重载接口为 ck_stop & ck_start
status/st:   检查程序健康状态, 重载接口为 ck_status

$(user_usage)
other:       打印这个帮助

tips:        其他接口有待进一步丰富，依赖于基础库 lib.sh
             路径：${BIN_PATH/lib.sh}

             *目前提供如下功能，待丰富和进一步抽象：*
             F1 - 定义一些常用的全局常量，如果有必要则在自己的脚本中重新赋值
             F2 - 定义运维维护所需的日志函数
             F3 - 定义运维维护所需的报警函数
             F4 - 定义进程pid检查和杀死的函数
             F5 - 定义模块全量备份：建议在执行 stop 接口的时候添加
             F6 - 定义模块启动的依赖检查项，根据需要进行组合检查
             F7 - 定义运维的全部接口，如果有必要则进行重新定义

             在特定模块的运维脚本中引用(source)该文件，并作如下定制化
             a. 重新赋值一些变量，重新定义一些接口
                ck_health  pre_start  cmd_start  pre_stop  cmd_stop
             b. 脚本最后添加 action [start|stop|restart|re|status|st]
HD_USAGE
}

# [重载接口][ck_health] 检查：模块运行健康检查，建议重新定义该函数
function ck_health() {
    #pstree work | grep -v "$CONTROL_NAME" | grep "$PRO_NAME" >/dev/null && return 0 || return 1
    # 默认为检查异常
    info "hey guys, maybe you need to override \"ck_health\""
    return 1
}

# [重载接口][ck_status] 状态：模块运行健康检查，内部调用 ck_health，如果有必要则重写
function ck_status() {
    ck_health && {
        notice "$PRO_NAME status: okay ~"
    } || {
        fatal "$PRO_NAME status: error !"
    }
}

# [重载接口][ck_start] 启动检查：默认为调用 ck_health，如果有必要则重写
function ck_start() {
    ck_health && return 0 || return 1
}

# [重载接口][pre_start] 启动之前：启动前置命令，建议重写
function pre_start() {
    info "hey guys, maybe you need to override \"pre_start\""
}

# [重载接口][cmd_start] 启动：启动程序的命令，建议重写
function cmd_start() {
    #cd $PRO_HOME || return 2
    #( ./bin/$PRO_NAME >/dev/null 2>&1 & )
    info "hey guys, maybe you need to override \"cmd_start\""
}

# [重载接口][ck_stop] 停止检查：默认为调用 ck_health，如果有必要则重写
function ck_stop() {
    ck_health && return 1 || return 0
}

# [重载接口][pre_stop] 停止之前：停止前置命令，建议重写
function pre_stop() {
    info "hey guys, maybe you need to override \"pre_stop\""
}

# [重载接口][cmd_stop] 停止：停止程序的命令，建议重写
function cmd_stop() {
    #killall $PRO_NAME || return 0
    info "hey guys, maybe you need to override \"cmd_stop\""
}

# [实现接口][start] 启动控制函数
function start() {

    ck_start && {
        fatal "$PRO_NAME already started !"
    }

    info "Trying to \"start\" $PRO_NAME"
    pre_start
    cmd_start

    wait_s=0
    while [[ $wait_s -lt $START_WAIT_TIME ]]
    do
        wait_s=`expr $wait_s + 1`
        sleep 1

        ck_start && {
            notice "$PRO_NAME start success !"
            return 0
        } || {
            warning "$PRO_NAME start checking failed, $wait_s times"
        }
    done

    fatal "Abort starting: $PRO_NAME start failed with trying $wait_s times"
}

# 停止控制函数，会尝试调用ck_stop判断是否停止成功
function stop() {

    ck_stop && {
        fatal "$PRO_NAME already stoped !"
    }

    info "Trying to \"stop\" $PRO_NAME"
    pre_stop
    cmd_stop

    wait_s=0
    while [[ $wait_s -lt $STOP_WAIT_TIME ]]
    do
        wait_s=`expr $wait_s + 1`
        sleep 1

        ck_stop && {
            notice "$PRO_NAME stop success !"
            return 0
        } || {
            warning "$PRO_NAME stop checking failed, $wait_s times"
        }
    done

    fatal "Abort stop: $PRO_NAME stop failed with trying $wait_s times"
}

