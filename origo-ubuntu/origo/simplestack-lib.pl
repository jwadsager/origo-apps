use JSON;
use Data::Dumper;
use URI::Encode qw(uri_encode uri_decode);
use WebminCore;
init_config();

sub get_internalip {
    my $internalip;
    if (!(-e "/tmp/internalip")) {
        $internalip = $1 if (`curl -sk https://10.0.0.1/steamengine/networks/this` =~ /"internalip" : "(.+)",/);
        chomp $internalip;
        `echo "$internalip" > /tmp/internalip` if ($internalip);
    } else {
        $internalip = `cat /tmp/internalip` if (-e "/tmp/internalip");
        chomp $internalip;
    }
    return $internalip;
}

sub get_externalip {
    my $externalip;
    if (!(-e "/tmp/externalip")) {
        $externalip = $1 if (`curl -sk https://10.0.0.1/steamengine/networks/this` =~ /"externalip" : "(.+)",/);
        chomp $externalip;
        if ($externalip eq '--') {
            # Assume we have eth1 up with an external IP address
            $externalip = `ifconfig eth1 | grep -o 'inet addr:\\\S*' | sed -n -e 's/^inet addr://p'`;
            chomp $externalip;
        }
        `echo "$externalip" > /tmp/externalip`;
    } else {
        $externalip = `cat /tmp/externalip` if (-e "/tmp/externalip");
        chomp $externalip;
    }
    return $externalip;
}

sub get_appid {
    my $appid;
    if (!(-e "/tmp/appid")) {
        $appid = $1 if (`curl -sk https://10.0.0.1/steamengine/servers?action=getappid` =~ /appid: (.+)/);
        chomp $appid;
        `echo "$appid" > /tmp/appid` if ($appid);
    } else {
        $appid = `cat /tmp/appid` if (-e "/tmp/appid");
        chomp $appid;
    }
    return $appid;
}

sub get_appinfo {
    my $appinfo;
    $appinfo = `curl -sk https://10.0.0.1/steamengine/servers?action=getappinfo`;
    my $json_hash_ref = from_json($appinfo);
    return $json_hash_ref;
}

sub list_simplestack_networks {
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/networks?system=this"`;
    $json_array_ref = from_json($json_text);
    return $json_array_ref;
}

sub list_simplestack_storagepools {
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/images?action=liststoragepools"`;
    $json_array_ref = from_json($json_text);
    return $json_array_ref;
}

sub get_network {
    my $domuuid = shift;
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/networks?system=$domuuid"`;
    $json_array_ref = from_json($json_text);
    my @json_array = @$json_array_ref;
    push @json_array, () unless (@json_array);
    return $json_array[0];
}

sub list_webmin_servers {
    foreign_require("servers", "servers-lib.pl");
    my @wservers = &foreign_call("servers", "list_servers");
    #foreach my $wserv (@wservers) {
    #    $wserv->{status} = ((&foreign_call("servers", "test_server", $wserv->{host}))?"unavailable":"ready");
    #}
    return @wservers;
}

sub save_webmin_server {
    my $host = shift;
    my $id = $host;
    my $s = {
              'user' => 'origo',
              'pass' => 'origo',
              'ssl' => '0',
              'file' => "/etc/webmin/servers/$id.serv",
              'port' => '10000',
              'host' => $host,
              'realhost' => '',
              'id' => $id,
              'type' => 'ubuntu',
              'fast' => '0'
            };
    foreign_require("servers", "servers-lib.pl");
    my $status = &foreign_call("servers", "save_server", $s);
    return $status;
}

sub delete_webmin_server {
    my $id = shift;
    foreign_require("servers", "servers-lib.pl");
    my $status = &foreign_call("servers", "delete_server", $id);
    return $status;
}

sub test_webmin_server {
    my $host = shift;
    foreign_require("servers", "servers-lib.pl");
    my $status = &foreign_call("servers", "test_server", $host);
    return $status;
}

sub show_me {
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/users/me"`;
    if ($json_text =~ /^\[/) {
        $json_hash_ref = from_json($json_text);
        return $json_hash_ref->[0];
    }
}

sub show_running_server {
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/servers/this"`;
    $json_hash_ref = from_json($json_text);
    return $json_hash_ref;
}

sub show_management_server {
    # Try twice
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/systems/this"`;
    if ($json_text =~ /^\[/) {
        $json_array_ref = from_json($json_text);
        return $json_array_ref->[0];
    } else {
        sleep 5;
        $json_text = `curl -ks "https://10.0.0.1/steamengine/systems/this"`;
        if ($json_text =~ /^\[/) {
            $json_array_ref = from_json($json_text);
            return $json_array_ref->[0];
        }
    }
}

sub modify_simplestack_server {
    my ($site) = @_;
    my $uuid = $site->{'uuid'};
    my $name = $site->{'name'};
    my $putdata = qq/{"uuid": "$uuid", "name": "$name"}/;
    my $cmd = qq[curl -ks -X PUT --data-urlencode 'PUTDATA=$putdata' https://10.0.0.1/steamengine/servers];
    my $reply = `$cmd`;
    return $reply;
}

sub apply_configuration {
    kill_byname_logged('HUP', 'simplestackd');
}

sub run_command {
    my $command = shift;
    my $skip_servers = shift;
    my $internalip = shift;
    foreign_require("cluster-shell", "cluster-shell-lib.pl");
    foreign_require("servers", "servers-lib.pl");
    my @servers = &foreign_call("servers", "list_servers");
    my @servs;

    # Make sure admin server is registered
    if (!@servers && $internalip) {
        save_webmin_server($internalip);
        @servers = &foreign_call("servers", "list_servers");
    }

    # Index actual servers so we don't run a command on a server that has been removed but is still in Webmin
    my $sservers_ref = list_simplestack_servers();
    @sservers = @$sservers_ref;
    my %sstatuses;
    foreach my $sserv (@sservers) {
        $sstatuses{$sserv->{internalip}} = $sserv->{status};
    }

    cancel_results();

    # Run one each one in parallel and display the output
    $p = 0;
    foreach $s (@servers) {
        next unless ($sstatuses{$s->{'host'}} eq 'running');
        next if ($skip_servers && $s->{'host'} eq $skip_servers);
        push @servs, $s->{'host'};
        `/usr/bin/mkfifo -m666 "/tmp/OPIPE-$s->{'host'}"` unless (-e "/tmp/OPIPE-$s->{'host'}");
        if (!fork()) {
            # Run the command in a subprocess
            close($rh);
            &remote_foreign_require($s->{'host'}, "webmin", "webmin-lib.pl");
            if ($inst_error_msg) {
                # Failed to contact host ..
                exit;
            }
            # Run the command and capture output
            local $q = quotemeta($command);
            local $rv = &remote_eval($s->{'host'}, "webmin", "\$x=`($q) </dev/null 2>&1`");
            my $result = &serialise_variable([ 1, $rv ]);
            `/bin/echo "$result" > "/tmp/OPIPE-$s->{'host'}"`;
            exit;
        }
        $p++;
    }
    return qq|{"status": "OK: Ran command $command on $p servers, $internalip", "servers": | . to_json(\@servs). "}";
}

sub get_results {
    # Get back all the results
    my $servers_ref = shift;
    my @servers = @$servers_ref;
    `pkill -f "/bin/cat < /tmp/OPIPE"`; # Terminate previous blocking reads that still hang
    $p = 0;
    my $res;
    foreach $d (@servers) {
        $line = `/bin/cat < /tmp/OPIPE-$d`; # Read from pipe - this blocks, eventually http read will time out
        local $rv = &unserialise_variable($line);
        my $result;
        if (!$line) {
            # Comms error with subprocess
            $res .= qq|<span class="label label-warning">$d failed to run the command for unknown reasons :(</span><br />\n|;
        } elsif (!$rv->[0]) {
            # Error with remote server
            $res .= qq|<span class="label label-warning">$d returned an error $rv->[1]</span><br />\n|;
        } else {
            # Done - show output
            $result = &html_escape($rv->[1]);
            chomp $result;
            if ($in{tab} eq 'software') {
                my $d2 = $d;
                $d2 =~ tr/./-/;
                my $disp = "display:none; ";
                if ($result =~ /Setting up/) {
                    $res .= qq|<span class="label label-success" style="cursor:pointer;" onclick='\$("#result-$d2").toggle();'>$d has been upgraded</span>\n|;
                    $res .= qq|<ul><pre id="result-$d2" style="max-height:160px; font-size:12px; overflow: auto; $disp">$result</pre></ul>\n|;
                } elsif ($result =~ /The following packages will be upgraded/) {
                    $res .= qq|<span class="label label-success upgrade-available" style="cursor:pointer;" onclick='\$("#result-$d2").toggle();'>$d has software upgrades available</span>\n|;
                    $res .= qq|<ul><pre id="result-$d2" style="max-height:160px; font-size:12px; overflow: auto; $disp">$result</pre></ul>\n|;
                } else {
                    $res .= qq|<span class="label label-success">$d has no software upgrades available</span><br />\n|;
                }
            } else {
                my $d2 = $d;
                $d2 =~ tr/./-/;
                my $disp = ($p==0)?'':"display:none; ";
                if ($result) {
                    $res .= qq|<span class="label label-success" style="cursor:pointer;" onclick='\$("#result-$d2").toggle();'>$d ran command succesfully</span>\n|;
                    $res .= qq|<ul><pre id="result-$d2" style="max-height:160px; font-size:12px; overflow: auto; $disp">$result</pre></ul>\n|;
                } else {
                    $res .= qq|<span class="label label-success">$d ran command succesfully</span><br />\n|;
                }
            }
        }
        $p++;
    }
    return $res;
}

sub cancel_results {
    `pkill -f "/bin/cat < /tmp/OPIPE"`; # Terminate previous blocking reads that still hang
}

sub list_simplestack_servers {
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/servers?system=this"`;
    $json_array_ref = from_json($json_text);
    return $json_array_ref;
}

# Check if a domain name
sub dns_check {
    my $name = shift;
    my $check = `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscheck\&name=$name"`;
    return ($check && $check =~ /^OK:/);
}

1;
