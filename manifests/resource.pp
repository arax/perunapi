define perunapi::resource (
  String                    $facility,
  Hash                      $resource,
  Stdlib::Fqdn              $context,
  Enum['present', 'absent'] $ensure     = 'present',
  Hash                      $attributes = {},
  Hash                      $services   = {},
) {

  if $ensure == 'absent' {
    fail('Cannot remove Resource via perunapi::resource, not implemented')
  }

  $api_user   = $perunapi::perun_api_user
  $api_host   = $perunapi::perun_api_host
  $api_passwd = $perunapi::perun_api_password

  ####

  $_query_fa = perunapi::call(
    $api_host, $api_user, $api_passwd, 'facilitiesManager', 'getFacilityByName',
    { 'name' => $facility }, $context
  )

  unless $_query_fa['id'] {
    fail("No facility named ${facility}")
  }
  $_facility_id = $_query_fa['id']

  ####

  $_query_vo = perunapi::call(
    $api_host, $api_user, $api_passwd, 'vosManager', 'getVoByShortName',
    { 'shortName' => $resource['vo'] }, $context
  )

  unless $_query_vo['id'] {
    fail("No VO named ${resource['vo']}")
  }
  $_vo_id = $_query_vo['id']

  $_query_res = perunapi::call(
    $api_host, $api_user, $api_passwd, 'resourcesManager', 'getResourceByName',
    { 'vo' => $_vo_id, 'facility' => $_facility_id, 'name' => $resource['name'] }, $context
  )

  if $_query_res['id'] {
    $_resource_id = $_query_res['id']
  } else {
    $_create_res = perunapi::call(
      $api_host, $api_user, $api_passwd, 'resourcesManager', 'createResource',
      {
        'resource' => { 'name' => $resource['name'], 'description' => $resource['description'] },
        'vo' => $_vo_id,
        'facility' => $_facility_id
      },
      $context
    )
    $_resource_id = $_create_res['id']

    notify { "createResource${resource['name']}${resource['vo']}":
      message => "Created resource ${resource['name']} for VO ${resource['vo']}",
    }
  }

  ####

  if $resource['tags'] {
    $_query_tags = perunapi::call(
      $api_host, $api_user, $api_passwd, 'resourcesManager', 'getAllResourcesTagsForResource',
      { 'resource' => $_resource_id }, $context
    )
    $_tags_name = $_query_tags.map |$_tag_obj| { $_tag_obj['tagName'] }

    $_query_all_tags = perunapi::call(
      $api_host, $api_user, $api_passwd, 'resourcesManager', 'getAllResourcesTagsForVo',
      {'vo' => $_vo_id }, $context
    )

    $resource['tags'].each |$_tag| {
      unless $_tag in $_tags_name {
        $_tag_obj = $_query_all_tags.filter |$_t| { $_t['tagName'] == $_tag }
        if empty($_tag_obj) {
          fail("Unknown tag ${_tag}")
        }

        perunapi::call(
          $api_host, $api_user, $api_passwd, 'resourcesManager', 'assignResourceTagToResource',
          { 'resourceTag' => $_tag_obj[0], 'resource' => $_resource_id }, $context
        )

        notify { "setTagForResource${_resource_id}${_tag}":
          message => "Assigned resource tag ${_tag} to resource ${resource['name']}",
        }
      }
    }
  }

  ####

  $_tmp_attributes = merge($attributes, $resource['attributes'])

  unless empty($_tmp_attributes) {
    $_pending_a = perunapi::callback($api_host, $api_user, $api_passwd, 'setAttribute', $context)
    if $_pending_a['endTime'] == -1 {
      notify { "setAttributeTimeout${_resource_id}":
        message => 'Pending set attribute request. Giving up.',
      }

      return()
    }

    $_filtered_data = $_tmp_attributes.filter |$key, $value| { $key =~ /:resource:/ }

    $_final_array = $_filtered_data.reduce([]) |Array $memo, Array $_item| {
      $_attribute = perunapi::call(
        $api_host, $api_user, $api_passwd, 'attributesManager', 'getAttribute',
        { 'resource' => $_resource_id, 'attributeName' => $_item[0] }, $context
      )

      if $_attribute['id'] {
        $_newattr = $_item[1] ? {
          'null' => undef,
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

    $_attributes_result = perunapi::call(
      $api_host, $api_user, $api_passwd, 'attributesManager', 'setAttributes',
      { 'resource' => $_resource_id, 'attributes' => $_final_array }, $context
    )

    if $_attributes_result['timeout'] {
      return()
    }

    if $_attributes_result['errorId'] and $_attributes_result['message'] {
      fail("Cannot set attributes. Reason: ${_attributes_result['message']}")
    }
  }

  ####

  unless empty($services) {
    $_pending_s = perunapi::callback($api_host, $api_user, $api_passwd, 'assignService', $context)
    if $_pending_s['endTime'] == -1 {
      notify { "assignServicesTimeout${_resource_id}":
        message => 'Pending assign service request. Giving up.',
      }

      return()
    }

    $services.each |$_service, $_service_value| {
      if $resource['name'] in $_service_value['resources'] {
        $_services_res = perunapi::call(
          $api_host, $api_user, $api_passwd, 'resourcesManager', 'getAssignedServices',
          { 'resource' => $_resource_id }, $context
        )

        $_services_list = $_services_res.map |$_s| { $_s['name'] }

        unless $_service in $_services_list {
          $_service_result = perunapi::call(
            $api_host, $api_user, $api_passwd, 'servicesManager', 'getServiceByName',
            { 'name' => $_service }, $context
          )

          if $_service_result['errorId'] and $_service_result['message'] {
            fail("Cannot get service ${_service}")
          }

          $_assign_resp = perunapi::call(
            $api_host, $api_user, $api_passwd, 'resourcesManager', 'assignService',
            { 'resource' => $_resource_id, 'service' => $_service_result['id'] }, $context
          )

          if $_assign_resp['timeout'] {
            notify { "assignService${_service}${_resource_id}_timeout":
              message => "Assigned service ${_service} to resource ${resource['name']} timeout. Stopping assigning more services.",
            }

            return()
          }

          notify { "assignService${_service}${_resource_id}":
            message => "Assigned service ${_service} to resource ${resource['name']} ${_assign_resp}",
          }
        }
      }
    }
  }

  ####

  if $resource['groupsfromresource'] {
    $_pending_g = perunapi::callback($api_host, $api_user, $api_passwd, 'assignGroupsToResource', $context)

    if $_pending_g['endTime'] == -1 {
      notify { "assignGroupsTimeout_${resource['groupsfromresource']}":
        message => 'Pending assign groups request. Giving up.',
      }

      return()
    }

    $_query_src = perunapi::call(
      $api_host, $api_user, $api_passwd, 'resourcesManager', 'getAssignedGroups',
      { 'resource' => $resource['groupsfromresource'] }, $context
    )

    if $_query_src =~ Hash and  $_query_src['errorId'] and $_query_src['message'] {
      fail("Cannot query source resource ${resource['groupsfromresource']} for groups. ${_query_src}")
    }

    $_query_dst = perunapi::call(
      $api_host, $api_user, $api_passwd, 'resourcesManager', 'getAssignedGroups',
      { 'resource' => $_resource_id }, $context
    )

    if $_query_dst =~ Hash and  $_query_dst['errorId'] and $_query_dst['message'] {
      fail("Cannot query destination resource ${_resource_id} for groups. ${_query_dst}")
    }

    $_add_groups = $_query_src - $_query_dst
    unless empty($_add_groups) {
      $_add_g_ids = $_add_groups.map |$_gr| { $_gr['id'] }
      $_res_gr = perunapi::call(
        $api_host, $api_user, $api_passwd, 'resourcesManager', 'assignGroupsToResource',
        { 'resource' => $_resource_id, 'groups' => $_add_g_ids }, $context
      )

      if $_res_gr['timeout'] {
        notify { "assignGroupsToResource_timeout_${_resource_id}":
          message => "Assign groups to resource ${resource['name']} timeout. Giving up",
        }

        return()
      }

      notify { "assignGroupsToResource${_resource_id}":
        message => "Assigned ${_add_g_ids} groups to resource ${resource['name']} ${_res_gr}",
      }
    }
  }
}
