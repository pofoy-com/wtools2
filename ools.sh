#!/bin/bash

# OpenLiteSpeed 默认安装目录
ols_root=/usr/local/lsws
# 虚拟机保存目录
vhs_root=/www
#
repo_raw=https://raw.githubusercontent.com/mina998/wtools/olstool
# 从网络获取本机IP(防止有些机器无法获取公网IP)
local_ip=$(wget -U Mozilla -qO - http://ip.42.pl/raw)
# 输出颜色
echo2(){
    if [ "$2" = "G" ]; then
        color="38;5;71"     #绿色
    elif [ "$2" = "B" ]; then
        color="38;1;34"     #蓝色
    elif [ "$2" = "Y" ]; then
        color="38;5;148"    #黄色
    else
        color="38;5;203"    #红色
    fi
    echo -e "\033[${color}m${1}\033[39m"
}
# 创建随机字符 最长32位
random_str(){
    if [ -z $1 ]; then
        echo $RANDOM |md5sum |cut -c 1-10
    else 
        echo $RANDOM |md5sum |cut -c 1-$1
    fi
}
# 检测数据库是否存在
isDBExist(){
    #判断数据库是否存在
    if [ ! -z `mysql -Nse "show DATABASES like '$1'"` ] ; then
        echo2 "数据库已存在"
        exit 0
    fi
}
# 获取配置
mysql_root_get(){
    echo $(grep 'MySQL密码' ~/.ols | cut -d : -f 2 | sed 's/ //')
}
# 获取系统信息
os_info(){
    #获取系统名称
    os_name=$(cat /etc/os-release | grep ^ID= | cut -d = -f 2)
    #获取系统版本
    if [ -f /etc/lsb-release ]; then
        os_ver=$(cat /etc/lsb-release | grep DISTRIB_CODENAME | cut -d = -f 2)
    else
        os_ver=$(cat /etc/os-release | grep VERSION= | sed -r 's/VERSION=".*\(([a-z]+)\)"/\1/')
    fi
}
# 创建防火墙规则
creat_firewall_rule(){
    #是否存在
    if [ -f /usr/sbin/iptables ]; then
        #下载防火墙规则
        wget -qO - $repo_raw/files/firewall > /etc/iptables.rules
        #下载重启自动加载文件
        wget -P /etc $repo_raw/files/rc.local
        #添加执行权限
        chmod +x /etc/rc.local
        #启动服务
        systemctl start rc-local
        #
        echo2 "重写防火墙规则" Y
    fi
}
# 安装面板
install_ols(){
    #判断面板是否安装
    if [ -e $ols_root/bin/lswsctrl ] ; then
        echo2 "OpenLiteSpeed 已存在"
        exit 0
    fi
    #创建虚拟机保存目录
    if [ -d $vhs_root ]; then
        echo2 "无法创建保存虚拟机的根目录, 请确保没有${vhs_root}文件夹"
        exit 0
    fi
    mkdir -p $vhs_root
    #添加存储库
    wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debian_repo.sh | bash
    #安装面板
    apt install openlitespeed -y
    #安装WordPress 的 PHP 扩展
    if [ -e $ols_root/lsphp74/bin/lsphp ] ; then
        #wordpress 必须组件 lsphp74-redis lsphp74-memcached
        apt install lsphp74-imagick lsphp74-curl lsphp74-intl -y
    fi
    #添加监听器
    wget -qO - $repo_raw/files/listener >> $ols_root/conf/httpd_config.conf
    #创建密钥文件
    wget -N -P $ols_root/conf $repo_raw/files/example.key && chmod 0600 $ols_root/conf/example.key
    #创建证书文件
    wget -N -P $ols_root/conf $repo_raw/files/example.crt && chmod 0600 $ols_root/conf/example.crt
    #重新加载配置
    service lsws force-reload
    #
    echo2 "面板安装完成" G
    echo "初始面板地址: https://${local_ip}:7080" >> .ols
    echo "初始面板账号: $(cat $ols_root/adminpasswd | cut -d ' ' -f 4 | cut -d '/' -f 1)" >> .ols
    echo "初始面板密码: $(cat $ols_root/adminpasswd | cut -d ' ' -f 4 | cut -d '/' -f 2)" >> .ols
}
# 安装MariaDB数据库服务
install_maria_db(){
    #判断是否安装过MariaDB
    if [ -e /usr/bin/mariadb ] ; then
        echo2 "MariaDB 已存在"
        exit 0
    fi
    os_info
    #添加密钥
    curl -o /etc/apt/trusted.gpg.d/mariadb_release_signing_key.asc 'https://mariadb.org/mariadb_release_signing_key.asc'
    #选择系统
    sh -c "echo 'deb https://mirrors.gigenet.com/mariadb/repo/10.5/$os_name $os_ver main' >>/etc/apt/sources.list"
    #开始安装
    apt update && apt install mariadb-server -y
    #重启防止出错
    systemctl restart mariadb
    echo2 "MariaDB安装完成" G
    #创建密码
    root_pwd=$(random_str 12)
    #设置密码
    mysql -uroot -e "flush privileges;"
    mysqladmin -u root password $root_pwd
    echo "MySQL账号: root" >> .ols
    echo "MySQL密码: $root_pwd" >> .ols
}
# 获取域名DNS解析
dns_domain_test(){
    #判断域名是否有解析
    if (ping -c 2 $1 &>/dev/null); then
        #获取域名解析IP
        domain_ip=$(ping "$1" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
    else 
        echo2 "[$1]:域名解析失败"
        exit 0
    fi
    #判断是否解析成功
    if [[ $local_ip = $domain_ip ]] ; then
        echo2 "[$1]域名DNS解析IP: $domain_ip" G
    else
        echo2 "[$1]:域名解析目标不正确."
        exit 0
    fi
}
# 获取域名
get_domain(){
    #获取输入
    echo -e "\033[32m"
    read -p "域名参数-m 主域名 -d 额外域名 (eg: -m demo.com -d www.demo.com):" domain
    echo -e "\033[0m"
    #提取域名列表
    domain=$(echo $domain | tr -s ' ')
    local domain_list=($domain)
    #验证域名DNS
    for ((i=0; i<=${#domain_list[@]}; i++))
    do
        if [[ ${domain_list[$i]} = '-m' ]]; then
            main_domain=${domain_list[$i+1]}
            dns_domain_test $main_domain
        elif [[ ${domain_list[$i]} = '-d' ]]; then
            dns_domain_test ${domain_list[$i+1]}
        fi
    done
    # 
    if [[ -z $main_domain ]]; then
        echo2 '主域名不能为空!'
        exit 0
    fi
}
# 安装WordPress
install_wp(){
    #判断是否安装OLS
    if [ ! -e $ols_root/bin/lswsctrl ] ; then
        echo2 "OpenLiteSpeed 不存在"
        exit 0
    fi
    #接收域名
    get_domain
    #创建网站根目录
    mkdir -p $vhs_root/$main_domain/backup && cd $vhs_root/$main_domain
    #下载WP程序
    wget https://wordpress.org/latest.tar.gz
    #解压WP程序 并删除压缩文件
    tar -xf latest.tar.gz && rm latest.tar.gz
    #修改文件目录所有者
    chown -R nobody:nogroup wordpress/
    #目录权限
    find wordpress/ -type d -exec chmod 750 {} \;
    #文件权限
    find wordpress/ -type f -exec chmod 640 {} \;
    #创建网站配置目录
    mkdir $ols_root/conf/vhosts/$main_domain
    #下载虚拟主机配置文件
    wget -N -P $ols_root/conf/vhosts/$main_domain $repo_raw/files/vhconf.conf
    #在主配置文件中指定虚拟主机配置信息
    wget -qO - $repo_raw/files/domain | sed "s/\$domain/$main_domain/" >> $ols_root/conf/httpd_config.conf
    #
    local domain_list=$(echo $domain | sed -r 's/-d|-m//g' | sed -r 's/^\s+|\s+$//g' | sed -r 's/\s+/,/g')
    #添加网站端口
    sed -i "/listener HTTPs {/a\map        $main_domain $domain_list" $ols_root/conf/httpd_config.conf
    sed -i "/listener HTTP {/a\map         $main_domain $domain_list" $ols_root/conf/httpd_config.conf
    #切换工作目录
    cd $ols_root/conf/vhosts
    #设置权限
    chown -R lsadm:nogroup $main_domain
    #重启服务
    service lsws restart
    #切换工作目录
    cd ~
    #设置数据库变量
    db_name="d`random_str`"
    db_user="u`random_str 12`"
    #检测数据库是否存在
    isDBExist $db_name
    #
    mysql_pass=$(mysql_root_get)
    #创建数据库和用户
    mysql -uroot -p$mysql_pass -Nse "create database $db_name"
    mysql -uroot -p$mysql_pass -Nse "grant all privileges on $db_name.* to '$db_user'@'%' identified by '$db_user'"
    mysql -uroot -p$mysql_pass -Nse "flush privileges"
    #定义变量
    admin_file=$vhs_root/$main_domain/backup/admin
    #删除存在的文件
    if [ -e $admin_file ]; then
        rm $admin_file
    fi
    echo "DB Name: $db_name" >> $admin_file
    echo "DB User: $db_user" >> $admin_file
    echo "DB Pass: $db_user" >> $admin_file
    echo2 "数据库信息: [cat $admin_file]" Y
    echo -e "\033[32m"
    cat $admin_file
    echo -e "\033[0m"
}
# 申请SSl证书
cert_ssl(){
    #获取域名
    get_domain "域名输入帮助[保证所有域名解析成功]: -m 主域名,添加站点时填写的域名. -d 其它额外域名"
    #判断站点是否存在
    if [[ ! -d $vhs_root/$main_domain ]]; then
        echo2 '站点不存在!'
        exit 0
    fi
    #下载安装证书签发程序
    if [ ! -f "/root/.acme.sh/acme.sh" ] ; then 
        curl https://get.acme.sh | sh -s email=admin@$main_domain
    fi
    #重新设置CA账户
    ~/.acme.sh/acme.sh --register-account -m admin@$main_domain
    #更改证书签发机构
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    #设置变量
    siteSSLSave=$ols_root/conf/vhosts/$main_domain && mkdir -p $siteSSLSave
    #获取所有域名
    domain=$(echo $domain | sed -r 's/-m\s+/-d /g' | tr -s ' ')
    #开使申请证书
    ~/.acme.sh/acme.sh --issue $domain --webroot $vhs_root/$main_domain/wordpress
    #证书签发是否成功
    if [ ! -f "/root/.acme.sh/$main_domain/fullchain.cer" ] ; then 
        echo2 "证书签发失败."
        exit 0
    fi
    #copy/安装 证书
    ~/.acme.sh/acme.sh --install-cert $domain --cert-file $siteSSLSave/cert.pem --key-file $siteSSLSave/key.pem --fullchain-file $siteSSLSave/fullchain.pem --reloadcmd "service lsws force-reload"
    # 
    echo2 "证书文件: $siteSSLSave/cert.pem" G
    echo2 "私钥文件: $siteSSLSave/key.pem"	G
    echo2 "证书全链: $siteSSLSave/fullchain.pem" G
}
# 安装phpMyAdmin
install_php_my_admin(){
    #
    if [ ! -d /usr/local/lsws/Example ]; then
        echo2 '目录不存在!'
        exit 0
    fi
    #切换工作目录
    cd /usr/local/lsws/Example
    #下载phpMyAdmin程序
    wget https://files.phpmyadmin.net/phpMyAdmin/4.9.10/phpMyAdmin-4.9.10-all-languages.zip
    #解压文件
    unzip phpMyAdmin-4.9.10-all-languages.zip > /dev/null 2>&1
    #删除文件
    rm phpMyAdmin-4.9.10-all-languages.zip
    #重命名文件夹
    mv phpMyAdmin-4.9.10-all-languages phpMyAdmin
    #切换目录
    cd phpMyAdmin
    #创建临时目录 并 设置权限
    mkdir tmp && chmod 777 tmp
    #创建Cookie密钥
    keybs="`random_str 32``random_str 32`"
    #修改配置文件1
    sed -i "/\$cfg\['blowfish_secret'\]/s/''/'$keybs'/" config.sample.inc.php
    #
    cd libraries
    #修改配置文件2
    sed -i "/\$cfg\['blowfish_secret'\]/s/''/'$keybs'/" config.default.php
    #导入sql文件
    mysql < /usr/local/lsws/Example/phpMyAdmin/sql/create_tables.sql
    #添加访问路径
    wget -qO - $repo_raw/files/phpMyAdmin >> $ols_root/conf/vhosts/Example/vhconf.conf
    #重启服务
    service lsws restart
    #
    cd ~
    echo "phpMyAdmin地址: http://$local_ip:8088/phpMyAdmin" >> .ols
    # echo2 "访问地址: http://$local_ip:8088/phpMyAdmin" G
}
# 重置面板用户名和密码
reset_ols_user_password(){
    echo2 '请设置面板用户名和密码' Y 
    bash /usr/local/lsws/admin/misc/admpass.sh
    #
    # sed "/面板密码/s/:.*/: 333333/" ~/.ols
}
# 显示面板信息
view_ols_info(){
    echo -e "\033[32m"
    cat ~/.ols
    echo -e "\033[0m"
}
# 设置菜单
menu(){
    echo2 "(1)安装OpenLiteSpeed 和 MariaDB" G
    echo2 "(2)安装phpMyAdmin" G
    echo2 "(3)添加WP站点" G
    echo2 "(4)申请SSL证书 [请先添加站点]" G
    echo2 "(5)重置面板用户名和密码" G
    echo2 "(6)查看OLS信息" G
    echo2 "(7)安装LSMCD缓存模块"

    read -p "请选择:" num
    if [ $num -eq 1 ] ; then
        apt update -y
        #安装所需工具
        apt-get install socat cron curl iputils-ping apt-transport-https -y
        creat_firewall_rule
        install_ols
        install_maria_db
        view_ols_info
    elif [ $num -eq 2 ] ; then
        install_php_my_admin
        view_ols_info
    elif [ $num -eq 3 ] ; then
        install_wp
    elif [ $num -eq 4 ] ; then
        cert_ssl
    elif [ $num -eq 5 ] ; then
        reset_ols_user_password
    elif [ $num -eq 6 ] ; then
        view_ols_info
    else
        echo2 "输入无效"
        exit 0
    fi
}

echo2 "该脚本只兼容Debian[9, 10, 11] 和 Ubuntu[18.04, 20.04] 其他系统未测试" Y
menu
