define perunapi::facility (
  Integer                   $vo,
  String                    $description,
  Stdlib::Fqdn              $cluster,
  Enum['present', 'absent'] $ensure      = 'present',
  Hash                      $manager     = { 'users' => [$perunapi::perun_api_user] },
  Array                     $owner       = [$perunapi::perun_api_user],
  Array                     $customhosts = [],
  Hash                      $attributes  = {},
  Hash                      $services    = {},
) {

  if $ensure == 'absent' {
    fail('Cannot remove Facility via perunapi::facility, not implemented')
  }

  $api_user   = $perunapi::perun_api_user
  $api_host   = $perunapi::perun_api_host
  $api_passwd = $perunapi::perun_api_password

  ####

  $_query = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'getFacilityByName',
                           { 'name' => $title }, $cluster)

  if $_query['name'] == 'FacilityNotExistsException' {
    notify{ 'create_facility':
       message => "Creating facility ${title}",
    }

    $_createfacility_req = { 'facility' => { 'id' => 0, 'name' => $title, 'description' => $description } }
    $_facility_result = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'createFacility',
                                       $_createfacility_req, $cluster)

    if $_facility_result['id'] {
       $_facility_id = $_facility_result['id']
    }
  } else {
    if $_query['id'] {
      $_facility_id = $_query['id']
    }
  }

  unless $_facility_id {
    fail("Did not find or create facility: ${title}")
  }

  ####

  $_query_admin_users = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'getAdmins',
                                       { 'facility' => $_facility_id, 'onlyDirectAdmins' => 'true' }, $cluster)
  $_adm_users = $_query_admin_users.map |$_user| { $_user['lastName'] }
  $_add_adm_users = $manager['users'] - $_adm_users

  $_add_adm_users.each |$_user| {
    notify{ 'addAdmins':
      message => "Adding admin user ${_user}",
    }

    $_query_user = perunapi::call($api_host, $api_user, $api_passwd, 'membersManager', 'findMembersInVo',
                                  { 'searchString' => $_user, 'vo' => $vo }, $cluster)
    if empty($_query_user) {
      fail("Did not find user ${_user}")
    }
    $_user_id = $_query_user[0]['userId']

    perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'addAdmin',
                   { 'facility' => $_facility_id , 'user' => $_user_id }, $cluster)
  }

  ####

  $_query_admin_groups = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'getAdminGroups',
                                        {'facility' => $_facility_id}, $cluster)
  $_adm_groups = $_query_admin_groups.map |$_group| { $_group['name'] }
  $_add_adm_groups = $manager['groups'] - $_adm_groups

  $_add_adm_groups.each |$_group| {
    notify{ 'addAdminGroups':
       message => "Adding admin group ${_group}",
    }

    $_query_group = perunapi::call($api_host, $api_user, $api_passwd, 'groupsManager', 'getGroupByName',
                                   { 'name' => $_group, 'vo' => $vo }, $cluster)
    if empty($_query_group) {
      fail("Did not find group ${_group}")
    }

    perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'addAdmin',
                   { 'facility' => $_facility_id , 'authorizedGroup' => $_query_group['id'] }, $cluster)
  }

  ####

  $_query_owners = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'getOwners',
                                  { 'facility' => $_facility_id }, $cluster)
  $_owners = $_query_owners.map |$_owner| { $_owner['name'] }
  $_add_owners = $owner - $_owners

  unless empty($_add_owners) {
    $_all_owners = perunapi::call($api_host, $api_user, $api_passwd, 'ownersManager', 'getOwners', {}, $cluster)
    $_add_owner_ids = $_all_owners.filter |$_owner| { $_owner['name'] in $_add_owners }.map |$_owner| { $_owner['id'] }

    $_add_owner_ids.each |$_id| {
      notify { 'addOwners':
        message => "Adding owner with ID ${_id} to facility ${title}",
      }

      perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'addOwner',
                     { 'facility' => $_facility_id, 'owner' => $_id }, $cluster)
    }
  }

  ####

  $_query_hosts = perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'getHosts',
                                 { 'facility' => $_facility_id }, $cluster)
  $_query_hostnames = $_query_hosts.map |$_host| { $_host['hostname'] }

  unless $facts['fqdn'] in $_query_hostnames {
    notify { 'addHost_self':
      message => "Adding host ${facts['fqdn']} to facility ${title}",
    }

    perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'addHost',
                   { 'facility' => $_facility_id, 'hostname' => $facts['fqdn'] }, $cluster)
  }

  $_add_customhosts = $customhosts - $_query_hostnames

  $_add_customhosts.each |$_host| {
    notify{ "addHost_${_host}":
      message => "Adding host ${_host} to facility ${title}",
    }

    perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'addHost',
                   { 'facility' => $_facility_id, 'hostname' => $_host }, $cluster)
  }

  $_dbhosts = puppetdb_query("resources { type = 'Perunapi::Host' and parameters.cluster = '${cluster}' }")
                .map |$_db_resource| { $_db_resource['parameters']['hostname'] }
  $_live_hosts = concat($_dbhosts, $customhosts)
  $_remove_hosts = $_query_hostnames - $_live_hosts

  $_remove_hosts.each |$_remove_host| {
    notify { "removed${_remove_host}":
      message => "Removed host ${_remove_host} from facility ${title}",
    }

    $_hostid = $_query_hosts.filter |$_f_host| { $_f_host['hostname'] == $_remove_host }
    perunapi::call($api_host, $api_user, $api_passwd, 'facilitiesManager', 'removeHost',
                   { "host" => $_hostid[0]['id'] }, $cluster)
  }

  ####

  $_filtered_data = $attributes.filter |$key, $value| { $key =~ /:facility:/ }

  $_tmp_array = $_filtered_data.reduce([]) |Array $memo, Array $_item| {
    $_attribute = perunapi::call($api_host, $api_user, $api_passwd, 'attributesManager', 'getAttribute',
                                 {'facility' => $_facility_id, 'attributeName' => $_item[0]}, $cluster)

    if $_attribute['id'] {
      $_newattr = $_item[1] ? {
        'null'  => undef,
        default => $_item[1],
      }

      if $_attribute['value'] != $_newattr {
        $memo + [merge($_attribute, { 'value' => $_newattr })]
      } else {
        # no change
        $memo
      }
    } else {
      notify { "Warning: undefined attribude name ${_item[0]}": }
      $memo
    }
  }

  unless empty($_final) {
    $_attributes_result = perunapi::call($api_host, $api_user, $api_passwd, 'attributesManager', 'setAttributes',
                                         { 'facility' => $_facility_id, 'attributes' => $_final }, $cluster)

    if $_attributes_result['timeout'] {
      return()
    }

    if $_attributes_result['errorId'] and $_attributes_result['message'] {
      fail("Cannot set attributes. Reason: ${_attributes_result['message']} Attributes: ${_final}")
    }
  }

  ####

  $services.each |$_service, $_service_hash| {
    $_service_result = perunapi::call($api_host, $api_user, $api_passwd, 'servicesManager', 'getServiceByName',
                                      {'name' => $_service}, $cluster)
    if $_service_result['errorId'] and $_service_result['message'] {
       fail("Cannot get service ID for ${_service}")
    }

    $_destination = $_service_hash['destination'] ? {
      'all'   => $facts['fqdn'],
      default => $_service_hash['destination'],
    }

    $_dest_res = perunapi::call($api_host, $api_user, $api_passwd, 'servicesManager', 'getDestinations',
                                {'service' => $_service_result['id'], 'facility' => $_facility_id}, $cluster)
    $_assigned_dests = $_dest_res.map |$_dest| { $_dest['destination'] }

    unless $_destination in $_assigned_dests {
      notify { "addDestinations_${_service}":
        message => "Adding destination ${_destination} to service ${_service}",
      }

      $_propagation = $_service_hash['propagation'] ? {
        NotUndef => $_service_hash['propagation'],
        default  => 'PARALLEL',
      }

      perunapi::call($api_host, $api_user, $api_passwd, 'servicesManager', 'addDestination',
                     { 'service' => $_service_result['id'], 'facility' => $_facility_id, 'destination' => $_destination,
                     'type' => $_service_hash['type'], 'propagationType' => $_propagation }, $cluster)
    }

    # remove only services on 'all' hosts, do not remove named hosts. hack for pbsmon_service
    if $_service_hash['destination'] == 'all' {
      $_remove_dests = $_assigned_dests - $_live_hosts

      $_remove_dests.each |$_r_dest| {
        perunapi::call($api_host, $api_user, $api_passwd, 'servicesManager', 'removeDestination',
                       { 'service' => $_service_result['id'], 'facility' => $_facility_id, 'destination' => $_r_dest,
                       'type' => $_service_hash['type'] }, $cluster)

        notify { "removeDest${_r_dest}${_service_id}":
          message => "Removed destination ${_r_dest} for service ${_service}",
        }
      }
    }
  }
}
