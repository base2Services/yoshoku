def parameters(params = [])
  params.each do | param |
    Parameter(param[:name]){ param[:type] }
  end
end

def do_mappings(maps = [])
  maps.each do | mapping |
    puts "hi"
    puts mapping[:name]
    puts mapping[:mapping]
    Mapping(mapping[:name], mapping[:mapping])
  end
end

#azs = [{A => 14, B => 12}]
def do_azs(azs = [])
  azs.each do |az, data|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", data[:range], ".0/24" ] ))
      Property('AvailabilityZone', FnSelect(data[:az_id], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-", Ref('RoleName') ,"-private#{az}"])
        }
      ])
    }
  end
end

def do_route_table_association(azs)
  azs.each do |az, data|
    availability_zones.each do |az|
      Resource("SubnetRouteTableAssociationPrivate#{az}") {
        Type 'AWS::EC2::SubnetRouteTableAssociation'
        Property('SubnetId', Ref("SubnetPrivate#{az}"))
        Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
      }
    end
  end
end

def vpc_security_group(name, comment, rules)
  Resource(name) {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', comment)
    Property('SecurityGroupIngress', rules)
  }
end

def launch_configuration(image_map_name, security_groups, instance_type, bootstrap_location)
  sgs = security_groups.map{|item| Ref(item)}
  LaunchConfiguration( :LaunchConfig ) {
    ImageId FnFindInMap(image_map_name, Ref('AWS::Region'),'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'KeyName')
    SecurityGroups sgs
    InstanceType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),instance_type)
    UserData FnBase64(FnJoin("",[
      "#!/bin/bash\n",
      "export NEW_HOSTNAME=", Ref('EnvironmentName') ,"-", Ref('RoleName') ,"-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\n",
      "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
      "hostname $NEW_HOSTNAME\n",
      "sed -i \"s/^\(HOSTNAME=\).*/\\1$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
      "echo \"127.0.0.2 $NEW_HOSTNAME\" >> /etc/hosts\n",
      "#{bootstrap_location} ", Ref("AWS::Region"), " ", Ref('AWS::AccountId'), "\n"
    ]))
  }
end

def auto_scaling_group(min_in_service, azs, launch_config, elb, health_check_key, min_key, max_key)
  subnets = []
  azs.each{|az, data| subnets << Ref("SubnetPrivate#{az}")}

  AutoScalingGroup("AutoScaleGroup") {
    UpdatePolicy("AutoScalingRollingUpdate", {
      "MinInstancesInService" => min_in_service,
      "MaxBatchSize"          => "1",
    })
    #TODO: refactor to map from azs
    #Question: do we need az if we have subnet?
    AvailabilityZones [
      FnSelect('0',FnGetAZs(Ref('AWS::Region'))),
      FnSelect('1',FnGetAZs(Ref('AWS::Region')))
    ]
    LaunchConfigurationName Ref(launch_config)
    LoadBalancerNames [ Ref(elb) ]
    HealthCheckGracePeriod '500'
    HealthCheckType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),health_check_key)
    MinSize FnFindInMap('EnvironmentType',Ref('EnvironmentType'),min_key)
    MaxSize FnFindInMap('EnvironmentType',Ref('EnvironmentType'),max_key)
    #TODO: refactor to map based on AZs
    VPCZoneIdentifier subnets
    addTag("Name", FnJoin("",[Ref("EnvironmentName"),"-", Ref('RoleName') ,"-xx"]), true)
    addTag("Environment", Ref("EnvironmentName"), true)
    addTag("EnvironmentType", Ref("EnvironmentType"), true)
    addTag("Role", Ref('RoleName'), true)
  }
end
