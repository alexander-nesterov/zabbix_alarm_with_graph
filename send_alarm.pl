#!/usr/bin/perl

use strict;
use warnings;
use MIME::Lite;
use LWP::Simple;
use File::Basename;
use POSIX;
use Switch;
use Cwd;
use JSON::RPC::Client;

my $file_logo = 'logo.png';
my $path_logo = '/usr/lib/zabbix/alertscripts/';
my $path_log = '/var/log/zabbix/send_alarm.log';

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
					item_last 		=> 'Последнее полученное значение:',
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
					item_last 		=> 'Last value:'
				},
);

my %regex = (
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

use constant
{
	MAX_LOG_SIZE 	=> 10,		#MB
	PERIOD 		=> 3600,	#3600 sec is 1 hour, 7200 sec is 2 hour
	WIDTH_GRAPH 	=> 800,
	HEIGHT_GRAPH 	=> 500,
	WIDTH_LOGO 	=> 100,
	HEIGHT_LOGO 	=> 100,
	LOGGING 	=> 'yes'
};

my $recipient;
my $subject;
my $message;
my $from;
my $mail_server;
my $zabbix_server;
my $zabbix_user;
my $zabbix_password;
my $language;

my $authID;

my $host_name;
my $host_ip;
my $host_alias;
my $host_description;

my $trigger_name;
my $trigger_status;
my $trigger_value;
my $trigger_severity;
my $trigger_nseverity;
my $trigger_expression;
my $trigger_description;
my $trigger_template;
my $trigger_id;

my $graph_id;

my $item_last;
my $graph_rnd;

&main();

################################################################################
#Send message
################################################################################
sub send_message
{

    my ($recipient, $from, $subject, $message, $file) = @_;

    my $body = &create_html($file);

    &write_log_to_file('Body:');
    &write_log_to_file($body);

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
	$msg->attach(
	    Type => 'image/jpeg',
	    Id   => $file,
	    Path => $path_logo . $file,
	);
    }

    $msg->attach(
	Type => 'image/gif',
	Id   => $file_logo,
	Path => $path_logo . $file_logo,
    );

    $msg->send('smtp', $mail_server);

    &delete_file($path_logo . $file);

    &write_log_to_file("Email Sent: $recipient Successfully");

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

    my $color_trigger_severity 	= $color_trigger_severity{$trigger_nseverity};
    my $color_trigger_value 	= $color_trigger_value{$trigger_value};

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
							<td>$host_name</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_alias'}</td>
							<td>$host_alias</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_ip'}</td>
							<td>$host_ip</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'host_description'}</td>
							<td>$host_description</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_name'}</td>
							<td>$trigger_name</td>
						</tr>
						<tr bgcolor="$color_trigger_value">
							<td>$field_description{$language}{'trigger_status'}</td>
							<td>$trigger_status</td>
						</tr>
						<tr bgcolor="$color_trigger_severity">
							<td>$field_description{$language}{'trigger_severity'}</td>
							<td>$trigger_severity</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_expression'}</td>
							<td>$trigger_expression</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_description'}</td>
							<td>$trigger_description</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'trigger_template'}</td>
							<td>$trigger_template</td>
						</tr>
						<tr>
							<td>$field_description{$language}{'item_last'}</td>
							<td>$item_last</td>
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
					    <img src="cid:$file_logo" width="$width_logo" height="$height_logo" alt="logo"/>
					    </body>
					    </html>
					};

    &write_log_to_file('Create HTML successfully');

    return $html;
}

################################################################################
#Get current path
################################################################################
sub get_current_path
{
    my $path = cwd();

    return $path;
}

################################################################################
#Download graph
################################################################################
sub download_graph
{

    my ($file, $graphid) = @_;
    #my $current_path = &get_current_path();
    my $period = PERIOD;
    my $width_graph = WIDTH_GRAPH;

    getstore("http://$zabbix_server/chart2.php?graphid=$graphid&period=$period&width=$width_graph", "/usr/lib/zabbix/alertscripts/$file");

    #&write_log_to_file("Path for download: $current_path");
    #&write_log_to_file("Download file: $current_path/$file successfuly");
}

################################################################################
#Delete graph
################################################################################
sub delete_file
{

    my $file = shift;

    unlink $file;

    &write_log_to_file("Delete file: $file successfuly");
}

################################################################################
#Generation name of graph
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
			user => $zabbix_user,
			password => $zabbix_password
		},
		id => 1
	    };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("START = zabbix_auth = Authentication failed");
	exit 1;
    }

    $authID = $response->content->{'result'};

    &write_log_to_file("API* Authentication successful.Auth ID: $authID");

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
	&write_log_to_file("Logout failed");
	exit 1;
    }

    undef $response;

    &write_log_to_file("API* Logout successful. Auth ID: $authID");
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

    &write_log_to_file("API* Host ID: $host_id");

    #undef $response;

    return $host_id;
}

################################################################################
#Get count graphs
################################################################################
sub get_graphs_count
{

    #my $host_id = shift;
    my $host_id = &zabbix_get_hostid($host_name);
    my $graphs_count;
    my $response;

    my $json = {
                jsonrpc => "2.0",
                method => "graph.get",
                params => {
                	hostids => "$host_id",
                	countOutput => "1",
                },
                id => 1,
                auth => "$authID",
                };

    $response = &send($json);

    if (!defined($response))
    {
	&write_log_to_file("graph.get.get(countOutput) failed");
	exit 1;
    }

    $graphs_count = $response->content->{'result'};

    &write_log_to_file("API* Graphs count: $graphs_count");

    undef $response;

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

    &write_log_to_file("API* Graphs for $host_name:");

    foreach my $graphs(@{$response->content->{'result'}}) 
    {
	foreach my $graph(@{$graphs->{'graphs'}}) 
	{
	    $graph_id = $graph->{'graphid'}; 
	    &write_log_to_file("\t| $i) Graph ID: $graph->{'graphid'} | Graph name: $graph->{'name'}");
	    &get_items_from_graphs($graph->{'graphid'});
	    $i++;
	}
    }

    ($response, $graph_name) = ();
}

################################################################################
#Get item
################################################################################
sub get_items_with_triggers
{

    my $host_name = shift;
    my $i = 1;
    my $item_trigger;
    my $response;

    my $json = {
                jsonrpc => "2.0",
                method => "item.get",
                params => {
                	output => "extend",
                	selectTriggers => ["triggerid", "description"],
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
	&write_log_to_file("host.get(selectTriggers) failed");
	exit 1;
    }

    &write_log_to_file("API* Item with triggers for $host_name:");

    foreach my $items(@{$response->content->{'result'}}) 
    {
	foreach my $item(@{$items->{'triggers'}}) 
	{
	    &write_log_to_file("\t| $i) Trigger ID: $item->{'triggerid'} | Trigger name: $item->{'description'}");
	    $i++;
	}
    }

    undef $response;
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
	    &write_log_to_file("\t\t|| $i) Item ID: $item->{'itemid'} | Item name: $item->{'name'}");
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
	    #&write_log_to_file("\t\t\t||| $i) Trigger ID: $trigger->{'triggerid'} | Trigger name: $trigger->{'description'}");

	    if ($trigger_id == $triggerid)
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

	my $size = &convert_to_mb(&get_size($path_log));

	if ($size > MAX_LOG_SIZE)
	{
	    &delete_file($path_log);
	}

	#open(my $fh, '>>', $path_log) or die "Can't open file $path_log";

	#my $date_time = localtime();

	#print $fh "$date_time - $log\n" if defined $log;

	#close $fh;
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
#Send to server
################################################################################
sub send
{
    my $json = shift;
    my $response;
    my $url = "http://$zabbix_server/api_jsonrpc.php";
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
	#
	#Script parameters
	#

	if ($parameter =~ m/(?<=recipient:)\s*([a-z0-9.-]+\@[a-z0-9.-]+)/sm)
	{
	    $recipient = &trim($1);
	    &write_log_to_file("Parameter* recipient => $recipient");
	}
	if ($parameter =~ m/(?<=subject:)\s*(.*?)$/sm)
	{
	    $subject = &trim($1);
	    &write_log_to_file("Parameter* subject => $subject");
	}
	if ($parameter =~ m/(?<=from:)\s*(.*?)$/sm)
	{
	    $from = &trim($1);
	    &write_log_to_file("Parameter* from => $from");
	}
	if ($parameter =~ m/(?<=mail-server:)\s*(.*?)$/sm)
	{
	    $mail_server = &trim($1);
	    &write_log_to_file("Parameter* mail-server => $mail_server");
	}
	if ($parameter =~ m/(?<=zabbix-server:)\s*(.*?)$/sm)
	{
	    $zabbix_server = &trim($1);
	    &write_log_to_file("Parameter* zabbix-server => $zabbix_server");
	}
	if ($parameter =~ m/(?<=zabbix-user:)\s*(.*?)$/sm)
	{
	    $zabbix_user = &trim($1);
	    &write_log_to_file("Parameter* zabbix-user => $zabbix_user");
	}
	if ($parameter =~ m/(?<=zabbix-password:)\s*(.*?)$/sm)
	{
	    $zabbix_password = &trim($1);
	    &write_log_to_file("Parameter* zabbix-password => $zabbix_password");
	}
	if ($parameter =~ m/(?<=language:)\s*(.*?)$/sm)
	{
	    $language = &trim($1);
	    &write_log_to_file("Parameter* language => $1");
	}

	#
	#Message
	#

	#Host
	if ($parameter =~ m/(?<=Host[\s*]name:)\s*(.*?)$/sm)
	{
	    $host_name = &trim($1);
	    &write_log_to_file("Parameter* host name => $host_name");
	}
	if ($parameter =~ m/(?<=Host[\s*]alias:)\s*(.*?)$/sm)
	{
	    $host_alias = &trim($1);
	    &write_log_to_file("Parameter* host alias => $host_alias");
	}
	if ($parameter =~ m/(?<=Host[\s*]IP:)\s*(.*?)$/sm)
	{
	    $host_ip = &trim($1);
	    &write_log_to_file("Parameter* host ip => $host_ip");
	}
	if ($parameter =~ m/(?<=Host[\s*]description:)\s*(.*?)$/sm)
	{
	    $host_description = &trim($1);
	    &write_log_to_file("Parameter* host description => $host_description");
	}

	#Trigger
	if ($parameter =~ m/(?<=Trigger[\s*]name:)\s*(.*?)$/sm)
	{
	    $trigger_name = &trim($1);
	    &write_log_to_file("Parameter* trigger name => $trigger_name");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]status:)\s*(.*?)$/sm)
	{
	    $trigger_status = &trim($1);
	    &write_log_to_file("Parameter* trigger status => $trigger_status");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]value:)\s*(.*?)$/sm)
	{
	    $trigger_value = &trim($1);
	    &write_log_to_file("Parameter* trigger value => $trigger_value");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]severity:)\s*(.*?)$/sm)
	{
	    $trigger_severity = &trim($1);
	    &write_log_to_file("Parameter* trigger severity => $trigger_severity");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]nseverity:)\s*(.*?)$/sm)
	{
	    $trigger_nseverity = &trim($1);
	    &write_log_to_file("Parameter* trigger nseverity => $trigger_nseverity");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]expression:)\s*(.*?)$/sm)
	{
	    $trigger_expression = &trim($1);
	    &write_log_to_file("Parameter* trigger expression => $trigger_expression");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]description:)\s*(.*?)$/sm)
	{
	    $trigger_description = &trim($1);
	    &write_log_to_file("Parameter* trigger description => $trigger_description");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]template:)\s*(.*?)$/sm)
	{
	    $trigger_template = &trim($1);
	    &write_log_to_file("Parameter* trigger template => $trigger_template");
	}
	if ($parameter =~ m/(?<=Trigger[\s*]ID:)\s*(.*?)$/sm)
	{
	    $trigger_id = &trim($1);
	    &write_log_to_file("Parameter* trigger ID => $trigger_id");
	}

	#Item
	if ($parameter =~ m/(?<=Last[\s*]value:)\s*(.*?)$/sm)
	{
	    $item_last = &trim($1);
	    &write_log_to_file("Parameter* last value => $item_last");
	}
    }
}

################################################################################
#Main procedure
################################################################################
sub main
{
    my $current_path = &get_current_path();

    print $current_path;

    &write_log_to_file('============= START =============');

    &parse_argv();

    #Auth
    &zabbix_auth();

    &get_graphs_count();
    &get_graphs($host_name);
    &get_items_with_triggers($host_name);

    #Logout
    &zabbix_logout;

    #Send message
    &send_message($recipient, $from, $subject, $message, $graph_rnd);

    &write_log_to_file('============== END ==============');
}
