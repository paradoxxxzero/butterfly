module.exports = (grunt) ->

  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')

    uglify:
      options:
        banner: '/*! <%= pkg.name %>
           <%= grunt.template.today("yyyy-mm-dd") %> */\n'
        sourceMap: true

      butterfly:
        files:
          'butterfly/static/main.min.js': 'butterfly/static/main.js'
          'butterfly/static/ext.min.js': 'butterfly/static/ext.js'

    sass:
      options:
        includePaths: ['butterfly/sass/']

      butterfly:
        expand: true
        cwd: 'butterfly/sass/'
        src: '*.sass'
        dest: 'butterfly/static/'
        ext: '.css'

    coffee:
      options:
        sourceMap: true

      butterfly:
        files:
          'butterfly/static/main.js': 'coffees/*.coffee'
          'butterfly/static/ext.js':  'coffees/ext/*.coffee'

    coffeelint:
      butterfly:
        'coffees/**/*.coffee'

    watch:
      options:
        livereload: true
      coffee:
        files: [
          'coffees/ext/*.coffee'
          'coffees/*.coffee'
          'Gruntfile.coffee'
        ]
        tasks: ['coffeelint', 'coffee']

      sass:
        files: [
          'butterfly/sass/*.sass'
        ]
        tasks: ['sass']

  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-contrib-cssmin'
  grunt.loadNpmTasks 'grunt-coffeelint'
  grunt.loadNpmTasks 'grunt-sass'
  grunt.registerTask 'dev', [
    'coffeelint', 'coffee', 'sass', 'watch']
  grunt.registerTask 'css', ['sass']
  grunt.registerTask 'default', [
    'coffeelint', 'coffee', 'sass', 'uglify']
