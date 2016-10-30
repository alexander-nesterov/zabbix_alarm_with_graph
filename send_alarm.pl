#!/usr/bin/perl

use strict;
use warnings;
use MIME::Lite;
use LWP::Simple;
use File::Basename('fileparse', 'dirname');
use POSIX;
use Switch;
use Cwd('abs_path');
use JSON::RPC::Client;

my $logo = '/usr/lib/zabbix/alertscripts/logo.png';
my $log_file = '/var/log/zabbix/send_alarm.log';

my %color_trigger_value = (
			    0 => '00CC00',	#OK
			    1 => 'CC0000'	#PROBLEM
);

my %color_trigger_severity = (
			    0 => '97AAB3',	#Not classified
			    1 => '7499FF',	#Information
			    2 => 'FFC859',	#Warning
			    3 => 'FFA059',	#Average
			    4 => 'E97659',	#High
			    5 => 'E45959'	#Disaster
);

my %field_description = (
			    ru =>	{
					host_name 		=> 'Имя узла сети:',
					host_alias 		=> 'Видимое имя узла:',
					host_ip 		=> 'IP адрес:',
					host_description 	=> 'Описание узла:',
					trigger_name 		=> 'Триггер:',
					trigger_status 		=> 'Статус триггера:',
					trigger_severity 	=> 'Важность триггера:',
					trigger_expression 	=> 'Выражение триггера:',
					trigger_description	=> 'Описание триггера:',
					trigger_template 	=> 'Шаблон:',
					last_value 		=> 'Последнее полученное значение:',
				},
			    en =>	{
					host_name 		=> 'Host name:',
					host_alias 		=> 'Host alias:',
					host_ip 		=> 'IP address:',
					host_description 	=> 'Host description:',
					trigger_name 		=> 'Trigger:',
					trigger_status 		=> 'Trigger status:',
					trigger_severity 	=> 'Trigger severity:',
					trigger_expression 	=> 'Trigger expression:',
					trigger_description 	=> 'Trigger description:',
					trigger_template 	=> 'Template:',
					last_value 		=> 'Last value:'
				},
);

my %rx = (
	recipient 			=> '(?<=recipient:)\s*([a-z0-9.-]+\@[a-z0-9.-]+)',
	subject 			=> '(?<=subject:)\s*(.*?)$',
	from 				=> '(?<=from:)\s*(.*?)$',
	mail_server 			=> '(?<=mail-server:)\s*(.*?)$',
	zabbix_server			=> '(?<=zabbix-server:)\s*(.*?)$',
	zabbix_user 			=> '(?<=zabbix-user:)\s*(.*?)$',
	zabbix_password 		=> '(?<=zabbix-password:)\s*(.*?)$',
	language 			=> '(?<=language:)\s*(.*?)$',
	host_name 			=> '(?<=Host[\s*]name:)\s*(.*?)$',
	host_alias 			=> '(?<=Host[\s*]alias:)\s*(.*?)$',
	host_ip 			=> '(?<=Host[\s*]IP:)\s*(.*?)$',
	host_description 		=> '(?<=Host[\s*]description:)\s*(.*?)$',
	trigger_name 			=> '(?<=Trigger[\s*]name:)\s*(.*?)$',
	trigger_status			=> '(?<=Trigger[\s*]status:)\s*(.*?)$',
	trigger_value			=> '(?<=Trigger[\s*]value:)\s*(.*?)$',
	trigger_severity 		=> '(?<=Trigger[\s*]severity:)\s*(.*?)$',
	trigger_nseverity		=> '(?<=Trigger[\s*]nseverity:)\s*(.*?)$',
	trigger_expression		=> '(?<=Trigger[\s*]expression:)\s*(.*?)$',
	trigger_description		=> '(?<=Trigger[\s*]description:)\s*(.*?)$',
	trigger_template 		=> '(?<=Trigger[\s*]template:)\s*(.*?)$',
	trigger_id 			=> '(?<=Trigger[\s*]ID:)\s*(.*?)$',
	last_value 			=> '(?<=Last[\s*]value:)\s*(.*?)$'
);

my %regex_result = ();

use constant
{
	MAX_LOG_SIZE 	=> 2,		#MB
	PERIOD 		=> 3600,	#3600 sec is 1 hour, 7200 sec is 2 hour
	WIDTH_GRAPH 	=> 800,
	HEIGHT_GRAPH 	=> 500,
	WIDTH_LOGO 	=> 100,
	HEIGHT_LOGO 	=> 100,
	LOGGING 	=> 'yes'
};

my ($message, $authID, $graph_id, $graph_rnd);

&main();

################################################################################
#Send message
################################################################################
sub send_message
{
    my ($recipient, $from, $subject, $message, $file) = @_;

    my $body = &create_html($file);

    #for debug
    #&write_log_to_file('Body:');
    #&write_log_to_file($body);

    my $msg = MIME::Lite->new(
	From     => $from,
	To       => $recipient,
	Subject  => $subject,
	Type     => 'multipart/related'
    );

    $msg->attach(
	Type => 'text/html',
	Data => $body
    );

    if (defined $file)
    {
	#graph
	$msg->attach(
	    Type => 'image/jpeg',
	    Id   => $file,
	    Path => get_path($logo) . '/' . $file,
	);
    }

    #logo
    if (-e $logo)
    {
	$msg->attach(
	Type => 'image/gif',
	Id => get_file($logo),
	Path => $logo,
	);
    }

    $msg->send('smtp', $regex_result{'mail_server'});

    &delete_file(get_path($logo) . '/' . $file);

    &write_log_to_file("Email sent to $recipient => successfully");

    ($msg, $body) = ();
}

################################################################################
#Create HTML
################################################################################
sub create_html
{
    my $file		= shift;

    my $width_graph	= WIDTH_GRAPH;
    my $height_graph	= HEIGHT_GRAPH;
    my $width_logo	= WIDTH_LOGO;
    my $height_logo	= HEIGHT_LOGO;

    my $trigger_nseverity	= $regex_result{'trigger_nseverity'};
    my $trigger_value		= $regex_result{'trigger_value'};

    my $color_trigger_severity 	= $color_trigger_severity{$trigger_nseverity};
    my $color_trigger_value 	= $color_trigger_value{$trigger_value};

    my $file_logo		= get_file($logo);
    my $language		= $regex_result{'language'};

    my $html = qq{ <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
					<html xmlns="http://www.w3.org/1999/xhtml">
					<head>
					<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
						<style type="text/css">
						p {
							line-height: 1.0;
						}
						</style>
					</head>
					<body>
						<table border="1">
						<tr>
							<td>$field_description{$language}{'host_name'}</td>
							<td>$regex_result{'host_name'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_alias'}</td>
							<td>$regex_result{'host_alias'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_ip'}</td>
							<td>$regex_result{'host_ip'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_description'}</td>
							<td>$regex_result{'host_description'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_name'}</td>
							<td>$regex_result{'trigger_name'}</td>
						</tr>
						<tr bgcolor="$color_trigger_value">
							<td>$field_description{$language}{'trigger_status'}</td>
							<td>$regex_result{'trigger_status'}</td>
						</tr>
						<tr bgcolor="$color_trigger_severity">
							<td>$field_description{$language}{'trigger_severity'}</td>
							<td>$regex_result{'trigger_severity'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_expression'}</td>
							<td>$regex_result{'trigger_expression'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_description'}</td>
							<td>$regex_result{'trigger_description'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_template'}</td>
							<td>$regex_result{'trigger_template'}</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'last_value'}</td>
							<td>$regex_result{'last_value'}</td>
						</tr>
					</table>
					};
					
					if (defined $file)
					{
					    $html .= qq{
						<br/><img src="cid:$file" width="$width_graph" height="$height_graph" alt="zabbix_graph"/>
					    };
					}
					
					$html .= qq{
					    <br/><br/><p><b>Zabbix server</b></p>
						};
					
					if (-e $logo)
					{
					$html .= qq{
					    <img src="cid:$file_logo" width="$width_logo" height="$height_logo" alt="logo"/>
						};
					}
						
					$html .= qq{
					    </body>
					    </html>
					};

    &write_log_to_file('Create HTML => successfully');

    return $html;
}

################################################################################
#Download graph
################################################################################
sub download_graph
{
    my ($file, $graphid) = @_;
    my $period = PERIOD;
    my $width_graph = WIDTH_GRAPH;
    my $current_path = &get_current_path() . '/' . $file;

    getstore("http://$regex_result{'zabbix_server'}/chart2.php?graphid=$graphid&period=$period&width=$width_graph", $current_path);

    &write_log_to_file("Download file $current_path => successfuly");
}

################################################################################
#Delete file
################################################################################
sub delete_file
{
    my $file = shift;

    unlink $file;

    &write_log_to_file("Delete file $file => successfuly");
}

################################################################################
#Generation name for graph
################################################################################
sub get_random_prefix
{
    my $rnd;

    for (0..20) { $rnd .= chr( int(rand(25) + 65) ); }

    return "$rnd.png";
}

################################################################################
#Login
################################################################################
sub zabbix_auth
{
    my $response;

    my $json = {
		jsonrpc => "2.0",
		method => "user.login",
		params => {
			user => $regex_result{'zabbix_user'},
			password => $regex_result{'zabbix_password'}
		},
		id => 1
	    };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("API* authentication failed");
	exit 1;
    }

    $authID = $response->content->{'result'};

    &write_log_to_file("API* Authentication successful.Auth ID => $authID");

    undef $response;

    return $authID;
}

################################################################################
#Logout
################################################################################
sub zabbix_logout
{
    my $response;

    my $json = {
		jsonrpc => "2.0",
		method => "user.logout",
		params => {},
		id => 2,
		auth => $authID,
		};
	
    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("API* logout failed");
	exit 1;
    }

	&write_log_to_file("API* Logout successful.Auth ID => $authID");

    undef $response;
}

################################################################################
#Get host id by name
################################################################################
sub zabbix_get_hostid
{
    my $host_name = shift;
    my $response;
    my $host_id;

    my $json = {
                jsonrpc => "2.0",
                method => "host.get",
                params => {
                	output => ["hostid"],
                	filter => {
                		host => [$host_name],
                	},
                },
                id => 1,
                auth => "$authID",
                };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("host.get(hostid) failed");
	exit 1;
    }

    foreach my $host(@{$response->content->{'result'}})
    {
	$host_id = $host->{'hostid'};
    }

    &write_log_to_file("API* Host ID => $host_id");

    undef $response;

    return $host_id;
}

################################################################################
#Get graphs
################################################################################
sub get_graphs
{
    my $host_name = shift;
    my $graph_name;
    my $response;
    my $i = 1;

    my $json = {
                jsonrpc => "2.0",
                method => "host.get",
                params => {
                	output => ["hostid"],
                	selectGraphs => ["graphid", "name"],
                	filter => {
                		host => [$host_name],
                	},
                },
                id => 1,
                auth => "$authID",
                };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("host.get(selectGraphs) failed");
	exit 1;
    }

    foreach my $graphs(@{$response->content->{'result'}}) 
    {
	foreach my $graph(@{$graphs->{'graphs'}}) 
	{
	    $graph_id = $graph->{'graphid'};
	    &get_items_from_graphs($graph->{'graphid'});
	    $i++;
	}
    }

    ($response, $graph_name) = ();
}

################################################################################
#Get items from graphs
################################################################################
sub get_items_from_graphs
{
    my $graph_id = shift;
    my $i = 1;
    my $response;

    my $json = {
                jsonrpc => "2.0",
                method => "graph.get",
                params => {
                	output => "extend",
                	selectItems => ["itemid", "name"],
                	filter => {
                		graphid => [$graph_id],
                	},
                },
                id => 1,
                auth => "$authID",
                };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("graph.get(selectItems) failed");
	exit 1;
    }

    foreach my $items(@{$response->content->{'result'}}) 
    {
	foreach my $item(@{$items->{items}}) 
	{
	    &get_items_from_graphs_with_triggers($item->{'itemid'});
	    $i++;
	}
    }

    undef $response;
}

################################################################################
#Get item from graph and with trigger
################################################################################
sub get_items_from_graphs_with_triggers
{
    my $item_id = shift;
    my $i = 1;
    my $triggerid;
    my $response;

    my $json = {
                jsonrpc => "2.0",
                method => "item.get",
                params => {
                	output => "extend",
                	selectTriggers => ["triggerid", "description"],
                	filter => {
                		itemid => [$item_id],
                	},
                },
                id => 1,
                auth => "$authID",
                };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("item.get(selectTriggers) failed");
	exit 1;
    }

    foreach my $triggers(@{$response->content->{'result'}})
    {
	foreach my $trigger(@{$triggers->{'triggers'}})
	{
	    $triggerid = $trigger->{triggerid};

		if ($regex_result{'trigger_id'} == $triggerid)
	    {
		$graph_rnd = &get_random_prefix();
		&download_graph($graph_rnd, $graph_id);
	    }
	    $i++;
	}
    }

    ($json, $response) = ();
}

################################################################################
#Write to log file
################################################################################
sub write_log_to_file
{
    my $logging = LOGGING;

    if ($logging eq 'yes')
    {
	my ($log) = @_;

	my $size = &convert_to_mb(&get_size($log_file));

	if ($size > MAX_LOG_SIZE)
	{
	    &delete_file($log_file);
	}

	open(my $fh, '>>', $log_file) or die "Can't open file $log_file";

	my $date_time = localtime();

	print $fh "$date_time - $log\n" if defined $log;

	close $fh;
    }
}

################################################################################
#Get size of log file
################################################################################
sub get_size
{
    my $file = shift;

    my $size = -s $file;

    return $size;
}

################################################################################
#Convert to MB
################################################################################
sub convert_to_mb
{
    my $size = shift;

    return ceil( ($size / (1024 * 1024)) );
}

################################################################################
#Trim
################################################################################
sub trim
{
    my $s = shift;

    $s =~ s/^\s+|\s+$//g;

    return $s;
}

################################################################################
#Get current path
################################################################################
sub get_current_path
{
    my $current_path = dirname(abs_path($0));

    return $current_path;
}

################################################################################
#Get file from path
################################################################################
sub get_file
{
    my $path = shift;

    return fileparse($path);
}

################################################################################
#Get path from full path
################################################################################
sub get_path
{
    my $path = shift;

    return dirname($path);
}

################################################################################
#Send to server
################################################################################
sub send
{
    my $json = shift;
    my $response;
    my $url = "http://$regex_result{'zabbix_server'}/api_jsonrpc.php";
    my $client = new JSON::RPC::Client;

    $response = $client->call($url, $json);

    return $response;
}

################################################################################
#Parse
################################################################################
sub parse_argv
{
    foreach my $parameter(@ARGV)
    {
	while (my ($k, $v) = each %rx)
	{
	    if ($parameter =~ m/$v/sm)
	    {
		$regex_result{$k} = &trim($1);
		delete $rx{$k};
	    }
	}
    }
}

################################################################################
#Main procedure
################################################################################
sub main
{
    &write_log_to_file('============= START =============');

    &parse_argv();

    #Auth
    &zabbix_auth();

    &get_graphs($regex_result{'host_name'});

    #Logout
    &zabbix_logout;

    #Send message
    &send_message(	$regex_result{'recipient'},
			$regex_result{'from'},
			$regex_result{'subject'},
			$message,
			$graph_rnd
		);
    &write_log_to_file('============== END ==============');
}
