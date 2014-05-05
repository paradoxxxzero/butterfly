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


    sass_to_scss:
      butterfly:
        expand: true
        cwd: 'sass/'
        src: '*.sass'
        dest: 'butterfly/scss/'
        ext: '.scss'

    sass:
      butterfly:
        expand: true
        cwd: 'butterfly/scss'
        src: '*.scss'
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
        tasks: ['sass_to_scss', 'sass']

  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-contrib-cssmin'
  grunt.loadNpmTasks 'grunt-coffeelint'
  grunt.loadNpmTasks 'grunt-sass'
  grunt.loadNpmTasks 'grunt-sass-to-scss'

  grunt.registerTask 'dev', [
    'coffeelint', 'coffee', 'sass_to_scss', 'sass', 'watch']
  grunt.registerTask 'css', ['sass_to_scss', 'sass']
  grunt.registerTask 'default', [
    'coffeelint', 'coffee',
    'sass_to_scss', 'sass',
    'uglify']
