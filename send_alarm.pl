#!/usr/bin/perl

=begin comment
perl send_alarm.pl --server 'https://localhost' \
--user 'user' \
--pwd 'password' \
--smtp 'localhost' \
--from 'zabbix@example.ru' \
--period 7200 \
--to 'user@example.ru' \
--subject 'Test subject' \
--message 'test message' \
--debug 0
=cut

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use Getopt::Long qw(GetOptions);
use JSON qw(encode_json decode_json);
use MIME::Lite;
use MIME::Base64;
use Data::Dumper;

use constant IMAGE_WIDTH => 812;

my $DEBUG; #0 - False, 1 - True
my $ZABBIX_SERVER;
my $ZABBIX_AUTH_ID;

my %PRIORITY;
$PRIORITY{'Highest'} = 1;
$PRIORITY{'High'}    = 2;
$PRIORITY{'Normal'}  = 3;
$PRIORITY{'Low'}     = 4;
$PRIORITY{'Lowest'}  = 5;

my %COLOR_TRIGGER_VALUE;
$COLOR_TRIGGER_VALUE{0} = '00CC00'; #OK
$COLOR_TRIGGER_VALUE{1} = 'CC0000'; #PROBLEM

my %COLOR_TRIGGER_SEVERITY;
$COLOR_TRIGGER_SEVERITY{0} = '97AAB3';  #Not classified
$COLOR_TRIGGER_SEVERITY{1} = '7499FF';  #Information
$COLOR_TRIGGER_SEVERITY{2} = 'FFC859';  #Warning
$COLOR_TRIGGER_SEVERITY{3} = 'FFA059';  #Average
$COLOR_TRIGGER_SEVERITY{4} = 'E97659';  #High
$COLOR_TRIGGER_SEVERITY{4} = 'E45959';  #Disaster

#in Notepad++, Plugins->MIME Tools->Base64 Encode
my $LOGO = q{
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
Gj/weU+FuWK/eXVQAAAABJRU5ErkJggg==
};

main();

sub zabbix_auth
{
    my ($user, $pwd) = @_;

    my %data;

    $data{'jsonrpc'} = '2.0';
    $data{'method'} = 'user.login';
    $data{'params'}{'user'} = $user;
    $data{'params'}{'password'} = $pwd;
    $data{'id'} = 1;

    my $response = send_to_zabbix(\%data);
 
    $ZABBIX_AUTH_ID = get_result($response);
    do_debug("Auth ID: . $ZABBIX_AUTH_ID", 'SUCCESS');
}

sub zabbix_logout
{
    my %data;

    $data{'jsonrpc'} = '2.0';
    $data{'method'} = 'user.logout';
    $data{'params'} = [];
    $data{'auth'} = $ZABBIX_AUTH_ID;
    $data{'id'} = 1;

    my $response = send_to_zabbix(\%data);

    my $result = get_result($response);
    do_debug("Logout: $result", 'SUCCESS');
}

sub get_ids_graphs
{
    my ($hostname, $itemid) = @_;

    my %data;

    #https://www.zabbix.com/documentation/3.0/manual/api/reference/graph/get
    $data{'jsonrpc'} = '2.0';
    $data{'method'} = 'graph.get';
    $data{'params'}{'output'} = ['graphid'];
    $data{'params'}{'selectGraphDiscovery'} = ['graphid'];
    $data{'params'}{'filter'}{'host'} = $hostname;
    $data{'params'}{'selectGraphItems'} = ['itemid'];
    $data{'params'}{'sortfield'} = 'graphid';
    $data{'params'}{'sortorder'} = 'ASC';
    $data{'auth'} = $ZABBIX_AUTH_ID;
    $data{'id'} = 1;

    my $response = send_to_zabbix(\%data);

    my @ids_graphs;
    foreach my $graphs(@{$response->{'result'}}) 
    {
        foreach my $graph(@{$graphs->{'gitems'}})  
        {
            push @ids_graphs, $graphs->{'graphid'} if $graph->{'itemid'} == $itemid;
        }
    }
    return @ids_graphs;
}

sub send_to_zabbix
{
    my $data_ref = shift;

    my $json = encode_json($data_ref);
    my $ua = create_ua();

    my $response = $ua->post("$ZABBIX_SERVER/api_jsonrpc.php",
                             'Content_Type'  => 'application/json',
                             'Content'       => $json,
                             'Accept'        => 'application/json');

    if ($response->is_success)
    {
        my $content_decoded = decode_json($response->content);
        if (is_error($content_decoded))
        {
            do_debug('Error: ' . get_error($content_decoded), 'ERROR');
            exit(-1);
        }
        return $content_decoded;
    }
    else
    {
        do_debug('Error: ' . $response->status_line, 'ERROR');
        exit(-1);
    }
}

sub is_error
{
    my $content = shift;

    if ($content->{'error'})
    {
        return 1;
    }
    return 0;
}

sub get_result
{
    my $content = shift;

    return $content->{'result'};
}

sub get_error
{
    my $content = shift;

    return $content->{'error'}{'data'};
}

sub zabbix_get_graph
{
    my ($graphid, $period) = @_;

    my $ua = create_ua();

    my $url = "$ZABBIX_SERVER/chart2.php?graphid=$graphid&period=$period&isNow=1&width=" . IMAGE_WIDTH;

    my $req = HTTP::Request->new('POST' => $url);
    $req->content_type('image/png');
    $req->header('Cookie' => "tab=0; zbx_sessionid=$ZABBIX_AUTH_ID");

    my $res = $ua->request($req);
    return $res->content;
}

sub create_ua
{
    my $ua = LWP::UserAgent->new();

    $ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0x00);
    return $ua;
}

sub colored
{
    my ($text, $color) = @_;

    my %colors = ('red'     => 31,
                  'green'   => 32,
                  'yellow'  => 37
    );
    my $c = $colors{$color};
    return "\033[" . "$colors{$color}m" . $text . "\e[0m";
}

sub do_debug
{
    my ($text, $level) = @_;

    if ($DEBUG)
    {
        my %lev = ('ERROR'   => 'red',
                   'SUCCESS' => 'green',
                   'INFO'    => 'white'
        );
        print colored("$text\n", $lev{$level});
    }
}

sub send_email
{
    my ($email_body, $subject, $graph, $smtp, $email_from, $email_to) = @_;
 
    my $msg = MIME::Lite->new(
                                From    => $email_from,
                                To      => $email_to,
                                Subject => $subject,
                                Type    => 'multipart/related'
    );
    $msg->attach(Type => 'text/html', Data => $email_body);
    $msg->attach(Type => 'image/png', Filename => 'graph.png', Id => 'graph.png', Data => $graph) if defined($graph);
    $msg->attach(Type => 'image/png', Filename => 'logo.png', Id => 'logo.png', Data => decode_base64($LOGO));
    $msg->replace('X-Mailer' => 'Zabbix');
    $msg->add('X-Priority' => $PRIORITY{'Highest'});
    $msg->send('smtp', $smtp, Debug => $DEBUG);
}

sub set_email_body
{
    my $message = shift;
 
    my $hostname = get_hostname();
    my $zabbix_api_version = zabbix_get_api_version();

    my $css = q{
                <style type="text/css">
                    table.Zabbix {
                        border: 2px solid #D40000;
                        background-color: #EEE7DB;
                        text-align: left;
                        border-collapse: collapse;
                    }

                    table.Zabbix td, table.Zabbix {
                        border: 1px solid #AAAAAA;
                        padding: 3px 2px;
                    }

                    table.Zabbix tbody td {
                        font-size: 15px;
                        color: #333333;
                    }

                    table.Zabbix tr:nth-child(even) {
                        background: #F5C8BF;
                    }
                </style>
    };

    my $email_body = qq{
                        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
                        <html xmlns="http://www.w3.org/TR/REC-html401">
                            <head>
                                <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
                                $css
                            </head>
                            <body>
                                $message
                                <br><img src='cid:graph.png' alt='Graph'><br><br>
                                <img src='cid:logo.png' alt='Logo' width='150' height='39'><br>
                                <font color='#bfbfbf'>This message generated by Zabbix API $zabbix_api_version on $hostname</font>
                            </body>
                        </html>
    };
    return $email_body;
}

sub get_hostname
{
    return `hostname`;
}

sub zabbix_get_api_version
{
    my %data;

    $data{'jsonrpc'} = '2.0';
    $data{'method'} = 'apiinfo.version';
    $data{'params'} = [];
    $data{'id'} = 1;

    my $response = send_to_zabbix(\%data);
    return get_result($response);
}

sub parse_hostname
{
    my $message = shift;

    my ($hostname) = ($message =~ qr/<td>Host name:.*<\/td><td>(.*)<\/td>/);
    if (!defined($hostname))
    {
        do_debug('Error: I don\'t know nothing about $hostname', 'ERROR');
        exit(-1);
    }
    return $hostname;
}

sub parse_itemid
{
    my $message = shift;

    my ($itemid) = ($message =~ qr/<td>Item ID:.*<\/td><td>(.*)<\/td>/);
    if (!defined($itemid))
    {
        do_debug('Error: I don\'t know nothing about $itemid', 'ERROR');
        exit(-1);
    }
    return $itemid;
}

sub parse_argv
{
    my $zbx_server;
    my $zbx_user;
    my $zbx_pwd;
    my $smtp;
    my $email_from;
    my $period = 7200;
    my $email_to;
    my $subject = 'Subject is empty';
    my $message = 'Message is empty';
    my $debug = 0;

    #Alert script parameters
    #Supported since 3.0.0
    #{ALERT.MESSAGE}
    #{ALERT.SENDTO}
    #{ALERT.SUBJECT}
    #https://www.zabbix.com/documentation/4.0/manual/appendix/macros/supported_by_location
    GetOptions('server=s'  =>  \$zbx_server,       #Zabbix server
               'user=s'    =>  \$zbx_user,         #User
               'pwd=s'     =>  \$zbx_pwd,          #Password
               'smtp=s'    =>  \$smtp,      	   #SMTP relay
               'from=s'    =>  \$email_from,       #From
               'period=i'  =>  \$period,           #Period
               'to=s'      =>  \$email_to,         #Recipient
               'subject=s' =>  \$subject,          #Subject
               'message=s' =>  \$message,          #Message
               'debug=i'   =>  \$debug             #Debug

    ) or do { exit(-1); };

    if (!defined($zbx_server)     || 
        !defined($zbx_user)       ||
        !defined($zbx_pwd)
       )
    {
        do_debug('Option server requires an argument', 'ERROR');
        exit(-1);
    }
    return ($zbx_server, $zbx_user, $zbx_pwd, $smtp, $email_from, $period, $email_to, $subject, $message, $debug);
}

sub main
{
    my ($zbx_server, $zbx_user, $zbx_pwd, $smtp, $email_from, $period, $email_to, $subject, $message, $debug) = parse_argv();

    $ZABBIX_SERVER = $zbx_server;
    $DEBUG = $debug;

    my $hostname = parse_hostname($message);
    my $itemid = parse_itemid($message);

    zabbix_auth($zbx_user, $zbx_pwd);

    my @ids_graphs = get_ids_graphs($hostname, $itemid);

    my $graph = zabbix_get_graph($ids_graphs[0], $period) if scalar @ids_graphs > 0;

    my $email_body = set_email_body($message);

    send_email($email_body, $subject, $graph, $smtp, $email_from, $email_to);

    zabbix_logout();
}
