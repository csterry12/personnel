ctrlPressed = false
@app =
  init: ->
    $ =>
      @flashFade()
      $('[data-load-user]').live 'click', ->
        $('#sidebar').load $(this).data('load-user')
        no
      _.each ['profile', 'address', 'contact', 'permissions'], (data) ->
        $("[data-edit-#{data}]").live 'click', ->
          $("#sidebar_#{data}").append('<div/>')
          $("#sidebar_#{data}").children(':last').load $(this).data("edit-#{data}"), ->
            $("#sidebar_#{data}").children(':not(:last)').hide()
          no
        $("[data-cancel-#{data}]").live 'click', ->
          $("#sidebar_#{data}").children(':last').remove()
          $("#sidebar_#{data}").children().show()
          no
      $("[data-add-address]").live 'click', ->
        $("#sidebar_address").append('<div/>')
        $("#sidebar_address").children(':last').load $(this).data("add-address"), ->
          $("#sidebar_address").children(':not(:last)').hide()
        no
      $("#overlay").dialog
        autoOpen: false
        resizable: false
        modal: true
      $("a.button.close").live 'click', ->
        $("#overlay").dialog("close")
        $('.modal_dialog').removeClass('selected')
      $('.modal_dialog').live 'click', ->
        if ctrlPressed
          $(this).toggleClass('selected')
          no
        else
          $(this).addClass('selected')
          $("#overlay .contentWrap").load $(this).attr("href"), ->
            $("#overlay").dialog("open")
          no
      $("#visible").click ->
        $.post $(this).attr('href')+'?visible='+$(this).attr('checked')
      $("#check_month").click ->
        $.get $(this).attr('href')
        no
      $("th.sortable").click ->
        $("#sort_by").val($(this).attr('sort'))
        $("#find_form").submit()
      $(".user_select").live 'click', ->
        id = $(this).attr('id')
        $("td.cells.user_selected").removeClass('user_selected')
        $("td.cells").each ->
          if $.trim($(this).html())==id
            $(this).addClass('user_selected')
      $("#clear_selection").live 'click', ->
        $("td.cells.user_selected").removeClass('user_selected')
      $("[name*='shiftdate']").change ->
        app.reload_shift_numbers()
      $(".datetime_select").datetimepicker
        dateFormat: 'yy-mm-dd'
      $(".date_select").datepicker
        dateFormat: 'yy-mm-dd'
      $(window).keydown (evt) ->
        if (evt.which == 17)
          ctrlPressed = true
      $(window).keyup (evt) ->
        if (evt.which == 17)
          ctrlPressed = false


  flashFade: ->
    $('.flash-fade').children().each (i) ->
      setTimeout((=> $(this).fadeOut()), 250 + i * 1000)

  reload: -> location.reload()

  display_addresses: (id) ->
    $("#sidebar_address").load '/user/display_addresses', ->
      app.showAddTab(id)
    no

  display_addresses_admin: (user_id, id) ->
    $("#sidebar_address").load '/admin/users/'+user_id+'/display_addresses', ->
      app.showAddTab(id)
    no

  reload_section: ( section) ->
    $("#sidebar_"+section).load '/user/display_section?section='+section

  reload_section_admin: (user_id, section) ->
    $("#sidebar_"+section).load '/admin/users/'+user_id+'/display_section?section='+section

  showAddTab: (tab) ->
    $("div[id^='sidebar_address_']").hide()
    $("#sidebar_address_"+tab).show()
    no
  reload_shift_admin: ( shift) ->
    $("#shift_"+shift).load '/admin/schedule_shifts/'+shift, ->
      $("#overlay").dialog("close")
  check_day: (template, day) ->
    $.get '/admin/schedule_templates/'+template+'/check_day/?day='+day
    no
  check_month: (template) ->
    $.get '/admin/schedule_templates/'+template+'/check_month/'
    no
  show_users_admin: ->
    $("#template_users").load '/admin/schedule/show_users/?id='+$("#schedule_template").attr('val')
    $("#overlay").dialog("close")
  reload_shift_numbers: ->
    dt = $("#shift_shiftdate_1i").val()+'-'+$("#shift_shiftdate_2i").val()+'-'+$("#shift_shiftdate_3i").val()
    $("#shift_numbers").load '/events/available_shift_numbers/?date='+dt, ->
      if $("select#shift_number option").size() == 0
        $("#new_shift .navform").hide()
      else
        $("#new_shift .navform").show()
  reload_shift_numbers_admin: ->
    dt = $("#shift_shiftdate_1i").val()+'-'+$("#shift_shiftdate_2i").val()+'-'+$("#shift_shiftdate_3i").val()
    $("#shift_numbers").load '/admin/shifts/available_shift_numbers/?date='+dt+'&user_id='+$("#shift_user_id").val(), ->
      if $("select#shift_number option").size() == 0
        $("#new_shift .navform").hide()
      else
        $("#new_shift .navform").show()
  mass_update: (responsible, additional_attributes, user_id, is_modified) ->
    regex = /cell_(\d+)_(\d+)_(\d+)/
    $("td.modal_dialog.selected").each ->
      text = $(this).attr('id')
      match =text.match(regex)
      shift_id = match[1]
      line = match[2]
      day = match[3]
      $.post "/admin/schedule_cells",
        {shift: shift_id, line: line, day: day,
        'schedule_cell[responsible]': responsible,
        'schedule_cell[additional_attributes]': additional_attributes,
        'schedule_cell[user_id]': user_id,
        'schedule_cell[is_modified]': is_modified,
        }, ->
          app.check_day shift_id, day
    no
    app.show_users_admin()
    $("#overlay").dialog("close")

