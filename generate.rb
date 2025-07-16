require 'xcodeproj'

# 创建一个空工程
project = Xcodeproj::Project.new('MyApp.xcodeproj')
# 添一个 iOS app target
target = project.new_target(:application, 'MyApp', :ios, '15.0')
# 在工程的主 Group 下建一个 Sources 组
group = project.main_group.new_group('Sources')
# 把 test.swift 加进 Sources
file  = group.new_file('test.swift')
# 让 target 编译这个文件
target.add_file_references([file])
# 保存 .xcodeproj
project.save