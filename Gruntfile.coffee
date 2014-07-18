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

    sass:
      butterfly:
        expand: true
        cwd: 'butterfly/sass'
        src: '*.sass'
        dest: 'butterfly/static/'
        ext: '.css'

    coffee:
      options:
        sourceMap: true

      butterfly:
        files:
          'butterfly/static/main.js': [
            'coffees/term.coffee'
            'coffees/selection.coffee'
            'coffees/virtual_input.coffee'
            'coffees/main.coffee'
          ]

    coffeelint:
      butterfly:
        'coffees/*.coffee'

    watch:
      options:
        livereload: true
      coffee:
        files: [
          'coffees/*.coffee'
          'Gruntfile.coffee'
        ]
        tasks: ['coffeelint', 'coffee']

      sass:
        files: [
          'sass/*.sass'
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
