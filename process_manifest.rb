$LOAD_PATH.unshift File.dirname(__FILE__)

require "util"
require "yaml"
require "fileutils"
require "json"

if ARGV.count != 3
  puts "usage: #{$PROGRAM_NAME} container-manifests-dir velum-source-code-dir salt-dir"
  Process.exit 1
end

CONTAINERS_MANIFESTS_DIR = ARGV[0]
VELUM_SOURCE_CODE_DIR = ARGV[1]
SALT_DIR = ARGV[2]

CONTAINERS_MANIFESTS_ORIG_DIR = "/usr/share/caasp-container-manifests".freeze
SALT_ORIG_DIR = "/usr/share/salt/kubernetes".freeze

def container_volume(name:, path:)
  {
    "name"      => volume_name(name: name),
    "mountPath" => path
  }
end

def patch_annotation_image(annotation)
  # array of keys to process - makes it easy to add more later
  keys = ["pod.beta.kubernetes.io/init-containers"]

  keys.each do |k|
    if annotation.has_key? k
      init_cont_array = YAML.safe_load annotation[k]

      init_cont_array.each do |container|
        patch_container container
      end

      annotation[k] = init_cont_array.to_json
    end
  end
end

def registry_container_image(container)
  container_image = container["image"].gsub /__TAG__/, "latest"
  stage = ENV.fetch("STAGING", "release")
  stage == "release" ? container_image : "#{ENV["STAGING"]}/#{container_image}"
end

def patch_container_image(container)
  if container["image"] =~ /^sles12\/velum/
    container["image"] = "sles12/velum:development"
  elsif container["image"] =~ /^sles12/
    container["image"] = "docker-testing-registry.suse.de/#{registry_container_image container}"
    container["imagePullPolicy"] = "Always"
  else
    warn "unknown image #{container["image"]}; won't replace it"
  end
end

def patch_container_envvars(container)
  (container["env"] || []).each do |envvar|
    case envvar["name"]
    when "RAILS_ENV"
      envvar["value"] = "development"
    end
  end
end

def patch_container_volumes(container)
  container["volumeMounts"] ||= Array.new
  container["volumeMounts"].reject! do |volume_mount|
    volume_mount["name"] == "salt" ||
      (volume_mount["name"] != "salt-master-config-returner-credentials-conf" &&
       volume_mount["name"] =~ /^salt-master-config-/)
  end
  container["volumeMounts"] +=
    case container["name"]
    when "salt-master"
      [
        container_volume(name: "salt", path: SALT_ORIG_DIR),
        container_volume(name: "salt-master-config", path: "/etc/salt/master.d")
      ]
    when "salt-api"
      [
        container_volume(name: "salt-master-config", path: "/etc/salt/master.d")
      ]
    when /^velum-/
      [
        container_volume(name: "velum-source-code", path: "/srv/velum")
      ]
    when "dev-env-admin-node"
      [
        container_volume(name: "salt-admin-minion-config", path: "/etc/salt/minion.d"),
        container_volume(name: "salt-admin-minion-grains", path: "/etc/salt/grains")
      ]
    else
      []
    end
end

def patch_container(container)
  patch_container_image container
  patch_container_envvars container
  patch_container_volumes container
end

def patch_containers(yaml)
  yaml["spec"]["containers"].each do |container|
    patch_container container
  end
end

def patch_annotations(yaml)
  patch_annotation_image yaml["metadata"]["annotations"] || {}
end

def volume_name(name:)
  "dev-env-#{name}"
end

def host_volume(name:, path:)
  {
    "name"     => volume_name(name: name),
    "hostPath" => {
      "path" => path
    }
  }
end

def patch_host_container_manifests(volume)
  if volume["hostPath"] && volume["hostPath"]["path"] =~ %r{^#{CONTAINERS_MANIFESTS_ORIG_DIR}}
    volume["hostPath"]["path"] = volume["hostPath"]["path"].sub CONTAINERS_MANIFESTS_ORIG_DIR,
                                                                CONTAINERS_MANIFESTS_DIR
    true
  else
    false
  end
end

def patch_host_salt(volume)
  if volume["hostPath"]["path"] && volume["hostPath"]["path"] =~ %r{^#{SALT_ORIG_DIR}}
    volume["hostPath"]["path"] = volume["hostPath"]["path"].sub SALT_ORIG_DIR, SALT_DIR
    true
  else
    false
  end
end

def patch_root_dir(volume)
  if volume["hostPath"] && volume["hostPath"]["path"]
    host_path = File.join File.expand_path(File.join(File.dirname(__FILE__),
                                                     "tmp",
                                                     "fake-root")),
                         volume["hostPath"]["path"]
    volume["hostPath"]["path"] = host_path
    true
  else
    false
  end
end

def patch_host_volumes(yaml)
  yaml["spec"]["volumes"] ||= []
  yaml["spec"]["volumes"].each do |volume|
    patch_host_container_manifests(volume) || patch_host_salt(volume) || patch_root_dir(volume)
  end
  yaml["spec"]["volumes"].reject! do |volume|
    volume["name"] != "salt-master-config-returner-credentials-conf" &&
      volume["name"] =~ /^salt-master-config-/
  end
  yaml["spec"]["volumes"] += [
    host_volume(name: "velum-source-code", path: VELUM_SOURCE_CODE_DIR),
    host_volume(name: "salt", path: SALT_DIR),
    host_volume(name: "salt-master-config", path: File.join(salt_adapted_config_dir, "config",
                                                            "master.d")),
    host_volume(name: "salt-admin-minion-config", path: File.join(salt_adapted_config_dir, "config",
                                                                  "admin", "minion.d")),
    host_volume(name: "salt-admin-minion-grains", path: File.join(salt_adapted_config_dir, "config",
                                                            "admin", "grains"))
  ]
end

yaml = YAML.safe_load STDIN

patch_containers yaml
patch_host_volumes yaml
patch_annotations yaml

puts yaml.to_yaml
