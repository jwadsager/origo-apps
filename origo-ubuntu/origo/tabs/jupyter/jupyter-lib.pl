#!/usr/bin/perl

use MIME::Base64 qw( decode_base64 );

@userprops = ("username", "firstName", "lastName", "email", "phoneNumber");
@userpropnames = ("Username", "First name", "Last name", "Email", "Phone");

sub jupyter {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab
        my $drows;
        my $dheaders;
        my $i = 0;
        foreach my $prop (@userprops) {
            my $propname = $userpropnames[$i];
            $drows .= <<END
                <tr>
                    <td>$propname:</td><td class="passwordform"><input type="text" name="edituser_$prop" id="edituser_$prop" /></td>
                </tr>
END
;
            $dheaders .= "            <th>$propname</th>\n";
            $i++;
        }
        my $form = <<END
<div class="tab-pane" id="jupyter">
    <div style="width:100%; height:310px; overflow-y:scroll;">
      <table class="table table-condensed table-striped small" id="users_table" style="width: 100%; border:none;">
        <thead>
          <tr>
$dheaders
          </tr>
        </thead>
        <tbody>

        </tbody>
      </table>
    </div>
    <div style="margin-top:6px; padding-top:4px ; border-top:2px solid #DDDDDD">
        <button class="btn btn-default" id="update_users" title="Click to check refresh user list." rel="tooltip" data-placement="top" onclick="\$('[rel=tooltip]').tooltip('hide'); updateLinuxUsers(); return false;"><span class="glyphicon glyphicon-repeat" id="urglyph"></span></button>
        <button class="btn btn-default" id="new_user" title="Click to add a user." rel="tooltip" data-placement="top" onclick="\$('[rel=tooltip]').tooltip('hide'); editLinuxUser(); return false;">New user</button>
    </div>
</div>

<div class="modal" id="editUserDialog" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-body">
        <h4 class="modal-title" id="user_label">Edit user</h4>
        <form id="edit_user_form" class="small" method="post" action="index.cgi?action=savelinuxuser\&tab=jupyter" autocomplete="off">
            <table width="100\%" style="padding:2px;">
$drows
                <tr>
                    <td>Password:</td><td class="passwordform"><input type="text" name="edituser_pwd" id="edituser_pwd" value="" /></td>
                </tr>
            </table>
        </form>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-default pull-left" data-dismiss="modal" onclick="confirmUserAction('delete', \$('#edituser_cn').val());">Delete</button>
        <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn btn-primary" onclick="saveLinuxUser(\$('#edituser_username').val());">Save</button>
      </div>
    </div>
  </div>
</div>
END
;
        return $form;

    } elsif ($action eq 'js') {
# Generate and return javascript the UI for this tab needs

        my $editjs;
        my $newjs;
        my $tablejs;
        my $nprops = scalar @userprops;
        my $i=1;
        foreach my $prop (@userprops) {
            $editjs .= qq|\$('#edituser_$prop').val(editrow["$prop"]+"");\n|;
            $newjs .= qq|\$("#edituser_$prop").val("");\n|;
            $tablejs .= qq|{ data: "$prop" },\n|;
            $i++;
        }

        my $js = <<END
    \$(document).ready(function () {
        usersTable = \$('#users_table').DataTable({
//            scrollY: 280,
            searching: false,
            paging: false,
            columns: [
                $tablejs
            ],
            columnDefs: [
                {
                    targets: [ 0 ],
                    render: function ( data, type, row ) {
                                    return ('<a href="#" onclick="editLinuxUser(\\''+ data + '\\');">' + data +'</a>');
                                }
                },
                {
                    targets: [ 4 ],
                    visible: false,
                    searchable: false
                }
            ],
            ajax: {
                url: "index.cgi?tab=jupyter\&action=listlinuxusers",
                dataSrc: ""
            }
        });
    });

    function updateLinuxUsers() {
        \$('#update_users').prop( "disabled", true);
//        \$('#urglyph').attr('class','glyphicon glyphicon-refresh');
        usersTable.ajax.reload(function ( json ) {
                                        \$('#update_users').prop( "disabled", false);
//                                        \$('#urglyph').attr('class','glyphicon glyphicon-repeat');
                                    });
    }

    function editLinuxUser(username) {
        \$('#editUserDialog').modal({'backdrop': false, 'show': true});
        var editrow = [];
        if (username) {
            \$('#edituser_username').val(username);
            \$('#edituser_username').prop("readonly",true);
            \$.each(usersTable.data(), function(index, irow) {
                if (irow["username"] == username) editrow = irow;
            });
            \$('#user_label').html("Edit user");
        } else {
        // New user
            \$('#edituser_username').val('');
            \$('#edituser_username').prop("readonly",false);
            $newjs;
            \$('#user_label').html("New user");
        }
        \$('#edituser_pwd')[0].type = "password";
        // A little fight against auto-fill-out
        setTimeout(function(){
            \$('#edituser_pwd').val('');
            if (!editrow["telephoneNumber"]) \$('#edituser_telephoneNumber').val('');
        }, 100);
        \$('#edituser_cn').focus();
    }

    function saveLinuxUser(user) {
        var editrow = [];
        console.log("Saving user", user);

        \$.each(usersTable.data(), function(index, irow) {
            if (irow["cn"] == user) editrow = irow;
        });

        \$.each(editrow, function( prop, oldval ) {
            var newval = \$("#edituser_" + prop).val();
            if (!newval && oldval) \$("#edituser_" + prop).val("--");
        });

        \$.post( "index.cgi?action=savelinuxuser\&tab=jupyter", \$("#edit_user_form").serialize())
        .done(function( data ) {
            salert(data);
            updateLinuxUsers();
        })
        .fail(function() {
            salert( "An error occurred :(" );
        });

        \$('#edituser_pwd')[0].type = "text";
        \$('#editUserDialog').modal('hide');
        return(false);
    }

    function deleteLinuxUser() {
        var editrow = [];
        console.log("Deleting user", \$("#edituser_cn").val());

        \$.post( "index.cgi?action=deletelinuxuser\&tab=jupyter", \$("#edit_user_form").serialize())
        .done(function( data ) {
            salert(data);
            updateLinuxUsers();
        })
        .fail(function() {
            salert( "An error occurred :(" );
        });

        \$('#edituser_pwd')[0].type = "text";
        \$('#editUserDialog').modal('hide');
        return(false);
    }

    function confirmUserAction(action, cn) {
        if (action == 'delete') {
            \$('#confirmdialog').prop('actionform', "deleteLinuxUser");
            \$('#confirmdialog').modal({'backdrop': false, 'show': true});
            return false;
        }
    };


END
;
        return $js;

    } elsif ($action eq 'deletelinuxuser' && defined $in{edituser_username}) {
        my $res = "Content-type: text/html\n\n";
        my $user = $in{edituser_username};
            $cmdres .= `userdel "$in{edituser_username}"`;
            if ($cmdres eq '') {
                $res .= "User deleted: $in{edituser_username}";
                my $dir = "/home/$user";
                if (scalar <"$dir/*">) {
                    unless (-d "/archive") {
                        `mkdir -p /archive`;
                    }
                    my $datestr = localtime() . '';
                    `mv "/home/$user" "/archive/$user ($datestr)"`;
                    $res .= " User share not empty - archived. ";
                }
            } else {
                $res .= "User not deleted - there was a problem ($cmd, $cmdres)";
            }
        return $res;

    } elsif ($action eq 'savelinuxuser' && defined $in{edituser_username}) {
        my $res = "Content-type: text/html\n\n";
        my $cmd;
        my $cmdres;
        my $cmdalert;
        my $isnew;
	my $existing_user = `getent passwd "$in{edituser_username}" 2>\&1`;
        if ($existing_user eq '') {
            $isnew = 1;
            if ($in{edituser_username} && $in{edituser_pwd}) {
                $cmd = qq[useradd -m "$in{edituser_username}" -s /bin/false && echo "$in{edituser_username}":"$in{edituser_pwd}" | chpasswd];
#                $cmd .= qq[ --mail-address "$in{edituser_mail}"] if ($in{edituser_mail});
#                $cmd .= qq[ --telephone-number "$in{edituser_telephoneNumber}"] if ($in{edituser_telephoneNumber});
#                $cmd .= qq[ --given-name "$in{edituser_givenName}"] if ($in{edituser_givenName});
#                $cmd .= qq[ --surname "$in{edituser_sn}"] if ($in{edituser_sn});
                $cmdres .= `$cmd 2>\&1`;
                #`mkdir "/mnt/data/users/$in{edituser_cn}"`;
                #`chmod 777 "/mnt/data/users/$in{edituser_cn}"`;
            } else {
                $cmdalert .= "Please provide a username" if (!$in{edituserusername});
                $cmdalert .= "Please provide a password" if (!$cmdalert && !$in{edituser_pwd});
            }
        }
            if ($in{edituser_pwd} && !$isnew) {
                $cmd = qq[echo "$in{edituser_username}":"$in{edituser_pwd}" | chpasswd];
                $cmdres .=  `$cmd 2>\&1`;
                if ($cmdres !~ /password not changed/) {
                    $res .=  "The password was changed! ";
                } else {
                    $res .= "The password was NOT changed! ";
                }
            }
#        }

        if ($cmdalert) {
            $res .= $cmdalert;
        } elsif (!$cmd) {
            $res .= "Nothing to save";
        } elsif ($cmdres eq '') {
            $res .= "User saved: $cmd";
        } else {
            $res .= "User not saved ($cmd, $cmdres)";
        }
        return $res;

    } elsif ($action eq 'listlinuxusers') {
        my %users = getUsers();
        my $res = "Content-type: application/json\n\n";
        my @uarray = values %users;
        my $ujson = to_json(\@uarray, {pretty=>1});
        $res  .= $ujson;
        return $res;

# This is called from index.cgi (the UI)
    } elsif ($action eq 'upgrade') {
        my $res;
        my $srcloc = "/home";
        my $dumploc = $in{targetdir};

        if (-d $dumploc) {
            # Stop services
            `/etc/init.d/jupyterhub stop`;
            `/etc/init.d/nginx stop`;
            unless (-e "$srcloc/var/run/jupyterhub.pid") {
                # Copy configuration
                `rm -r "$dumploc/home.tgz"`;
                `(cd /; tar -zcf "$dumploc/home.tgz" home)`;
                `rm -r "$dumploc/jupyterhub_config.py"`;
                # Also copy /etc/samba
                `cp -r "/jupyterhub_config.py" "$dumploc/jupyterhub_config.py"`;
            }
        }

        my $dumpsize = `du -bs $dumploc/home.tgz`;
       $dumpsize = $1 if ($dumpsize =~ /(\d+)/);
        if ($dumpsize > 10000000) {
            $res = "OK: User home directories dumped successfully to $dumploc";
        } else {
            $res = "There was a problem dumping user directories to $dumploc ($dumpsize)!";
        }
        return $res;

# This is called from origo-ubuntu.pl when rebooting and with status "upgrading"
    } elsif ($action eq 'restore') {
        my $srcloc = $in{sourcedir};
        my $res;
        my $dumploc  = "/home";
        `bash -c "service jupyterhub stop"`;
        `bash -c "service nginx stop"`;
        if ($srcloc && -d $srcloc && -d $dumploc && !(-e "$srcloc/var/run/jupyterhub.pid")) {
            $res = "OK: ";

            my $srcfile = "home.tgz";
            $res .= qq|restoring $srcloc/$srcfile -> $dumploc, |;
            $res .= `bash -c "tar -zcf /tmp/home.bak.tgz /home"`;
           $res .= `bash -c "mv --backup /tmp/home.bak.tgz /home.bak.tgz"`;
            $res .= `bash -c "(cd /; tar -zxf $srcloc/$srcfile)"`;

            my $srcdir = "jupyterhub_config.py";
            $dumploc  = "/";
            $res .= qq|copying $srcloc/$srcdir -> $dumploc, |;
            $res .= `cp --backup -a $srcloc/$srcdir "$dumploc"`;

            chomp $res;
        }

        if ($res) {
            `service nginx start`;
            `service jupyterhub start`;
        } else {
            $res = "Not copying $srcloc -> $dumploc";
        }
#        `umount /mnt/fuel/*`;
        return $res;

}

sub getUsers {
    my %users;
    my $users_text = `cut -d: -f1 /etc/passwd`;
    foreach my $line (split /\n/, $users_text) {
        $users{$line}->{'username'} = $line;
    }
    foreach my $user (values %users) {
        foreach my $prop (@userprops) {
            $user->{$prop} = '' unless ($user->{$prop});
        }
    }
    return %users;
}

1;
