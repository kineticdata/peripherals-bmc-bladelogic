# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class BladelogicCommandRunV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'

    # Store parameters values in a Hash of parameter names to values.
    @parameters = {}
    REXML::XPath.match(@input_document, '/handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end

  def execute()
    app_server = @info_values['app_server']
    puts app_server

    puts "Configuring Savon" if @enable_debug_logging
    if !@enable_debug_logging
      Savon.configure do |config|
        config.log = false
        config.log_level = :error
        HTTPI.log = false
      end
    end

    # Create the client
    username = @info_values['server_domain'] + "\\" + @info_values['server_username']
    password = @info_values['server_password']
    client = Savon::Client.new do |wsdl,http,wsse|
      http.auth.basic username, password
      wsdl.document = app_server + "/services/BSALoginService.wsdl"
      wsdl.endpoint = app_server + "/services/LoginService"
    end

    # A self-signed certificate will not verify, so this ssl verify is turned
    # off so that openssl doesn't throw on excpetion when testing with a
    # self-signed certificate
    client.http.auth.ssl.verify_mode = :none if @info_values['self-signed_cert'].downcase == "true"

    # SOAP request to get list contents
    bl_user = @info_values['bladelogic_username']
    bl_pass = @info_values['bladelogic_password']
    response = client.request(:login_using_user_credential) do
      soap.body = {:userName => bl_user, :password => bl_pass, :authentication_type => "SRP"}
    end

    session_id = response.body[:login_using_user_credential_response][:return_session_id]

    # Create the client
    username = @info_values['server_domain'] + "\\" + @info_values['server_username']
    password = @info_values['server_password']
    client = Savon::Client.new do |wsdl,http,wsse|
      http.auth.basic username, password
      wsdl.document = app_server + "/services/BSAAssumeRoleService.wsdl"
      wsdl.endpoint = app_server + "/services/AssumeRoleService"
    end
    client.config.soap_header = {:"ins0:sessionId!" => session_id}

    # A self-signed certificate will not verify, so this ssl verify is turned
    # off so that openssl doesn't throw on excpetion when testing with a
    # self-signed certificate
    client.http.auth.ssl.verify_mode = :none if @info_values['self-signed_cert'].downcase == "true"

    # SOAP request to get list contents
    role = @info_values['bladelogic_role']
    response = client.request(:assume_role) do
      soap.body = {:role_name => role}
    end

    puts response.body.inspect

    # Create the client
    username = @info_values['server_domain'] + "\\" + @info_values['server_username']
    password = @info_values['server_password']
    client = Savon::Client.new do |wsdl,http,wsse|
      http.auth.basic username, password
      wsdl.document = app_server + "/services/BSACLITunnelService.wsdl"
      wsdl.endpoint = app_server + "/services/CLITunnelService"
    end
    client.config.soap_header = {:"ins1:sessionId!" => session_id}

    # A self-signed certificate will not verify, so this ssl verify is turned
    # off so that openssl doesn't throw on excpetion when testing with a
    # self-signed certificate
    client.http.auth.ssl.verify_mode = :none if @info_values['self-signed_cert'].downcase == "true"

    name_space = @parameters['name_space']
    command_name = @parameters['command_name']
    command_arguments = []

    if @parameters['command_argument_1'] != ""
      command_arguments.push(@parameters['command_argument_1'])
    end

    if @parameters['command_argument_2'] != ""
      command_arguments.push(@parameters['command_argument_2'])
    end

    if @parameters['command_argument_3'] != ""
      command_arguments.push(@parameters['command_argument_3'])
    end

    if @parameters['command_argument_4'] != ""
      command_arguments.push(@parameters['command_argument_4'])
    end

    if @parameters['command_argument_5'] != ""
      command_arguments.push(@parameters['command_argument_5'])
    end

    # SOAP request to get list contents
    response = client.request(:execute_command_by_param_list) do
      soap.body = {:name_space => name_space, :command_name => command_name, :command_arguments => command_arguments}
    end

    puts client.wsdl.soap_actions.inspect

    cli_response = response[:execute_command_by_param_list_response][:return][:return_value]
    
    # Return the results
    <<-RESULTS
    <results>
      <result name="cli_response">#{escape(cli_response)}</result>
    </results>
    RESULTS
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}

end