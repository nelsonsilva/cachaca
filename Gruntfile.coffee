module.exports = (grunt) ->
  grunt.initConfig(
    pkg: grunt.file.readJSON('package.json'),

    browserify:
      dist:
        files:
          'index.js': ['src/js/**/*.js', 'src/coffee/**/*.coffee'],
        options:
          transform: ['coffeeify']
          alias: [
            "src/coffee/dgram.coffee:dgram"
            "src/coffee/connect.coffee:connect"
          ]

    watch:
      files: [ "src/**/*.*" ],
      tasks: [ 'browserify' ]
    
  )

  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-browserify'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-usemin'

  grunt.registerTask 'default', 'Default task', (n) ->
    grunt.task.run 'browserify'