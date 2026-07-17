# recipes/default.rb — illustrative reconstruction of the generic Chef
# pattern the nginx role (roles/nginx/) replaces.
package 'nginx' do
  action :install
end

template '/etc/nginx/nginx.conf' do
  source 'nginx.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    worker_processes: node['nginx']['worker_processes'],
    worker_connections: node['nginx']['worker_connections']
  )
  notifies :reload, 'service[nginx]'
end

service 'nginx' do
  action [:enable, :start]
end
