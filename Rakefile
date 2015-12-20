require 'cfndsl/rake_task'
require 'rake'
require 'yaml'
require "net/http"
require "net/https"
require "uri"
require "aws-sdk"


namespace :cfn do

  #load config
  current_dir = File.dirname(File.expand_path(__FILE__))
  config = YAML.load(File.read("config/default_params.yml"))
  templates = Dir["templates/**/*.rb"]
  files = []
  templates.each do |template|
    filename = "#{template}"
    output = template.sub! 'templates/', ''
    output = output.sub! '.rb', '.json'
    files << { filename: filename, output: "output/#{output}" }
  end

  stack_name = ENV['stack_name'] || 'dev'
  environment_type = ENV['environment_type'] || 'dev'
  cf_version = ENV['cf_version'] || 'dev'
  rds_snapshot = ENV['rds_snapshot'] || ''
  enabled_activemq = ENV['enabled_activemq'] || 'true'
  stack_octet = ENV['stack_octet'] || '222'

  extra_files = Dir['config/*.yml']
  extras = []
  extra_files.each do |extra|
    extras << [:yaml, extra]
  end
  extras << [:raw, "cf_version='#{cf_version}'"]

  CfnDsl::RakeTask.new do |t|
    t.cfndsl_opts = {
      verbose: true,
      files: files,
      extras: extras
    }
  end

  desc('validate cloudformation templates')
  task :validate do
    Dir["output/**/*.json"].each do |t|
      file = File.expand_path(t)
      puts("validating template: #{file}" )
      cmd = ['aws','cloudformation', 'validate-template', "--template-body file://#{file}"]
      config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
      config['source_region'].nil? ? '' : cmd << "--region #{config['source_region']}"
      args = cmd.join(" ")
      puts "executing: #{args}"
      result = `#{args}`
      puts result
      if $?.to_i > 0
        puts "fail to validate #{t} template"
        exit $?.to_i
      end
    end
  end

  desc("Build and validate cloudformation")
  task :build_validate => [:generate] do
    Rake::Task["validate"].reenable
    Rake::Task["validate"].invoke
  end

  desc('deploy cloudformation templates to S3')
  task :deploy do
    cmd = ['s3', 'sync', '--delete', 'output/', "s3://#{config['source_bucket']}/cloudformation/#{cf_version}/"]
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['source_region'].nil? ? '' : cmd << "--region #{config['source_region']}"
    args = cmd.join(" ")
    puts "executing: aws #{args}"
    result = `aws #{args}`
    puts result
    if $?.to_i > 0
      puts "fail to upload rendered templates to S3 bucket #{config['source_bucket']}"
      exit $?.to_i
    else
      puts "Successfully uploaded rendered templates to S3 bucket #{config['source_bucket']}"
    end
  end

  desc('creates an environment')
  task :create do
    cmd = ['aws','cloudformation', 'create-stack', "--stack-name #{stack_name}", "--template-url https://s3-#{config['source_region']}.amazonaws.com/#{config['source_bucket']}/cloudformation/#{cf_version}/master.json", '--capabilities CAPABILITY_IAM']
    cmd << "--parameters ParameterKey=EnvironmentName,ParameterValue=#{stack_name} ParameterKey=EnvironmentType,ParameterValue=#{environment_type} ParameterKey=ActiveMQEnabled,ParameterValue=#{enabled_activemq} ParameterKey=RDSSnapshotID,ParameterValue=#{rds_snapshot}, ParameterKey=StackOctet,ParameterValue=#{stack_octet}"
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['source_region'].nil? ? '' : cmd << "--region #{config['source_region']}"
    args = cmd.join(" ")
    puts "executing: #{args}"
    result = `#{args}`
    puts result
    if $?.to_i > 0
      puts "fail to create environment"
      exit $?.to_i
    else
      puts "Starting creation of environment"
    end
  end

  desc('updates the environment')
  task :update do
    cmd = ['aws','cloudformation', 'update-stack', "--stack-name #{stack_name}", "--template-url https://s3-#{config['source_region']}.amazonaws.com/#{config['source_bucket']}/cloudformation/#{cf_version}/master.json", '--capabilities CAPABILITY_IAM']
    cmd << "--parameters ParameterKey=EnvironmentName,ParameterValue=#{stack_name} ParameterKey=EnvironmentType,ParameterValue=#{environment_type} ParameterKey=ActiveMQEnabled,UsePreviousValue=true ParameterKey=RDSSnapshotID,UsePreviousValue=true ParameterKey=StackOctet,UsePreviousValue=true"
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['source_region'].nil? ? '' : cmd << "--region #{config['source_region']}"
    args = cmd.join(" ")
    puts "executing: #{args}"
    result = `#{args}`
    puts result
    if $?.to_i > 0
      puts "fail to update environment"
      exit $?.to_i
    else
      puts "Starting updating of environment"
    end
  end

  desc('delete/tears down the environment')
  task :tear_down do
    cmd = ['aws','cloudformation', 'delete-stack', "--stack-name #{stack_name}"]
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['source_region'].nil? ? '' : cmd << "--region #{config['source_region']}"
    args = cmd.join(" ")
    puts "executing: #{args}"
    result = `#{args}`
    puts result
    if $?.to_i > 0
      puts "fail to tear down environment"
      exit $?.to_i
    else
      puts "Starting tear down of environment"
    end
  end

  desc('wait for app url')
  task :wait do
    wait_for_cfn config, stack_name
  end

  def wait_for_cfn (config, stack_name)
    puts "waiting for cloudformation for environment - #{stack_name}"
    stacks = []
    credentials = Aws::SharedCredentials.new(profile_name: 'acmeorgdev')
    if File.exists?("#{ENV['HOME']}/.aws/credentials")
      cfn = Aws::CloudFormation::Client.new(region: 'ap-southeast-2', credentials: credentials)
    else
      cfn = Aws::CloudFormation::Client.new(region: 'ap-southeast-2')
    end
    # get master stack status
    success = false
    until success
      stacks = cfn.list_stack_resources(stack_name: stack_name).stack_resource_summaries
      stacks.each do |event|
        puts "#{event.logical_resource_id} - #{event.resource_status}"
      end
      master = cfn.describe_stacks(stack_name: stack_name).stacks[0]
      case master.stack_status
      when 'CREATE_IN_PROGRESS'
        puts "stack #{stack_name} creation in-progress"
      when 'UPDATE_IN_PROGRESS'
        puts "stack #{stack_name} update in-progress"
      when 'CREATE_COMPLETE'
        puts "stack #{stack_name} creation complete"
      when 'UPDATE_COMPLETE'
        puts "stack #{stack_name} update complete"
      end
      success = stack_update_complete(master)
      sleep 10 unless success
    end
    if success
      puts "Environment #{stack_name} has been successfully updated"
    else
      puts "Environment #{stack_name} has failed to update"
      exit 1
    end
  end

  def stack_update_complete( stack )
    sucess_states  = ["CREATE_COMPLETE", "UPDATE_COMPLETE"]
    failure_states = ["CREATE_FAILED", "DELETE_FAILED", "UPDATE_ROLLBACK_FAILED", "ROLLBACK_FAILED", "ROLLBACK_COMPLETE","ROLLBACK_FAILED","UPDATE_ROLLBACK_COMPLETE","UPDATE_ROLLBACK_FAILED"]
    end_states     = sucess_states + failure_states
    end_states.include?(stack.stack_status)
  end

  def check_app_url (stack_name, environment_type, main_site_enabled)
    domain = environment_type == 'staging' ? 'dev.aws.x.com' : 'aws.x.com'
    if main_site_enabled == 'false'
      app_url = "https://preview.#{stack_name}.#{domain}/"
    else
      app_url = "https://#{stack_name}.#{domain}/auth/login"
    end
    puts "waiting for app #{app_url}"
    url = URI.parse(app_url)
    req = Net::HTTP.new(url.host, url.port)
    req.use_ssl = true
    req.verify_mode = OpenSSL::SSL::VERIFY_NONE
    count = 0
    while count < 30
      res = req.request_head(url.path)
      if res.code == "200"
        break
      end
      count += 1
      print "."
      sleep 10
    end
    if res.code == "200"
      puts "\n#{app_url} is now availale"
      exit 0
    else
      puts "\n#{app_url} is not availale"
      exit 1
    end
  end

end
