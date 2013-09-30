class App.TicketCreate extends App.Controller
  events:
    'click .customer_new': 'userNew'
    'submit form':         'submit'
    'click .submit':       'submit'
    'click .cancel':       'cancel'

  constructor: (params) ->
    super

    # check authentication
    return if !@authenticate()

    # set title
    @form_id = App.ControllerForm.formId()

    @edit_form = undefined

    # set article attributes
    default_type = 'call_inbound'
    if !@type
      @type = default_type
    article_sender_type_map =
      call_inbound:
        sender:  'Customer'
        article: 'phone'
        title:   'Call Inbound'
      call_outbound:
        sender:  'Agent'
        article: 'phone'
        title:   'Call Outbound'
      email:
        sender:  'Agent'
        article: 'email'
        title:   'Email'
    @article_attributes = article_sender_type_map[@type]

    # remember split info if exists
    split = ''
    if @ticket_id && @article_id
      split = "/#{@ticket_id}/#{@article_id}"

    # if no map entry exists, route to default
    if !@article_attributes
      @navigate '#ticket_create/' + default_type + split
      return

    # update navbar highlighting
    @navupdate '#ticket_create/' + @type + '/id/' + @id + split

    @fetch(params)

    # lisen if view need to be rerendert
    @bind 'ticket_create_rerender', (defaults) =>
      @log 'notice', 'error', defaults
      @render(defaults)

  meta: =>
    text = App.i18n.translateInline( @article_attributes['title'] )
    subject = @el.find('[name=subject]').val()
    if subject
      text = "#{text}: #{subject}"
    meta =
      url:   @url()
      head:  text
      title: text
      id:    @type

  url: =>
    '#ticket_create/' + @type + '/id/' + @id

  activate: =>
    @navupdate '#'
    @el.find('textarea').elastic()

  changed: =>
    formCurrent = @formParam( @el.find('.ticket-create') )
    diff = difference( @formDefault, formCurrent )
    return false if !diff || _.isEmpty( diff )
    return true

  release: =>
    # nothing

  autosave: =>
    update = =>
      data = @formParam( @el.find('.ticket-create') )
      diff = difference( @autosaveLast, data )
      if !@autosaveLast || ( diff && !_.isEmpty( diff ) )
        @autosaveLast = data
        @log 'notice', 'form hash changed', diff, data
        App.TaskManager.update( @task_key, { 'state': data })
    @interval( update, 3000, @id )

  # get data / in case also ticket data for split
  fetch: (params) ->

    # use cache
    cache = App.Store.get( 'ticket_create_attributes' )

    if cache && !params.ticket_id && !params.article_id

      # get edit form attributes
      @edit_form = cache.edit_form

      # load collections
      App.Event.trigger 'loadAssets', cache.assets

      @render()
    else
      @ajax(
        id:    'ticket_create'
        type:  'GET'
        url:   @apiPath + '/ticket_create'
        data:
          ticket_id: params.ticket_id
          article_id: params.article_id
        processData: true
        success: (data, status, xhr) =>

          # cache request
          App.Store.write( 'ticket_create_attributes', data )

          # get edit form attributes
          @edit_form = data.edit_form

          # load collections
          App.Event.trigger 'loadAssets', data.assets

          # split ticket
          if data.split && data.split.ticket_id && data.split.article_id
            t = App.Ticket.find( params.ticket_id ).attributes()
            a = App.TicketArticle.find( params.article_id )

            # reset owner
            t.owner_id = 0
            t.customer_id_autocompletion = a.from
            t.subject = a.subject || t.title
            t.body = a.body

          # render page
          @render( options: t )
      )

  render: (template = {}) ->

    # set defaults
    defaults =
      ticket_state_id:    App.TicketState.findByAttribute( 'name', 'open' ).id
      ticket_priority_id: App.TicketPriority.findByAttribute( 'name', '2 normal' ).id

    # generate form
    configure_attributes = [
      { name: 'customer_id',        display: 'Customer', tag: 'autocompletion', type: 'text', limit: 200, null: false, relation: 'User', class: 'span7', autocapitalize: false, help: 'Select the customer of the Ticket or create one.', link: '<a href="" class="customer_new">&raquo;</a>', callback: @localUserInfo, source: @apiPath + '/users/search', minLengt: 2 },
      { name: 'group_id',           display: 'Group',    tag: 'select',   multiple: false, null: false, filter: @edit_form, nulloption: true, relation: 'Group', default: defaults['group_id'], class: 'span7',  },
      { name: 'owner_id',           display: 'Owner',    tag: 'select',   multiple: false, null: true,  filter: @edit_form, nulloption: true, relation: 'User',  default: defaults['owner_id'], class: 'span7',  },
      { name: 'tags',               display: 'Tags',     tag: 'tag',      type: 'text', null: true, default: defaults['tags'], class: 'span7', },
      { name: 'subject',            display: 'Subject',  tag: 'input',    type: 'text', limit: 200, null: false, default: defaults['subject'], class: 'span7', },
      { name: 'body',               display: 'Text',     tag: 'textarea', rows: 8,                  null: false, default: defaults['body'],    class: 'span7', upload: true },
      { name: 'ticket_state_id',    display: 'State',    tag: 'select',   multiple: false, null: false, filter: @edit_form, relation: 'TicketState',    default: defaults['ticket_state_id'],    translate: true, class: 'medium' },
      { name: 'ticket_priority_id', display: 'Priority', tag: 'select',   multiple: false, null: false, filter: @edit_form, relation: 'TicketPriority', default: defaults['ticket_priority_id'], translate: true, class: 'medium' },
    ]
    @html App.view('agent_ticket_create')(
      head:  'New Ticket'
      title: @article_attributes['title']
      agent: @isRole('Agent')
      admin: @isRole('Admin')
    )

    params = undefined
    if template && !_.isEmpty( template.options )
      params = template.options
    else if App.TaskManager.get(@task_key) && !_.isEmpty( App.TaskManager.get(@task_key).state )
      params = App.TaskManager.get(@task_key).state

    new App.ControllerForm(
      el: @el.find('.ticket_create')
      form_id: @form_id
      model:
        configure_attributes: configure_attributes
        className:            'create_' + @type + '_' + @id
      autofocus: true
      form_data: @edit_form
      params:    params
    )

    # add elastic to textarea
    @el.find('textarea').elastic()

    # update textarea size
    @el.find('textarea').trigger('change')

    # show template UI
    new App.WidgetTemplate(
      el:          @el.find('.ticket_template')
      template_id: template['id']
    )

    @formDefault = @formParam( @el.find('.ticket-create') )

    # show text module UI
    @textModule = new App.WidgetTextModule(
      el: @el.find('.ticket-create').find('textarea')
    )

    # start auto save
    @autosave()

  localUserInfo: (params) =>

    # update text module UI
    callback = (user) =>
      @textModule.reload(
        ticket:
          customer: user
      )

    @userInfo(
      user_id:  params.customer_id
      el:       @el.find('.customer_info')
      callback: callback
    )

  userNew: (e) =>
    e.preventDefault()
    new UserNew(
      create_screen: @
    )

  cancel: ->
    @navigate '#'

  submit: (e) ->
    e.preventDefault()

    # get params
    params = @formParam(e.target)

    # fillup params
    if !params.title
      params.title = params.subject

    # create ticket
    object = new App.Ticket

    # find sender_id
    sender = App.TicketArticleSender.findByAttribute( 'name', @article_attributes['sender'] )
    type   = App.TicketArticleType.findByAttribute( 'name', @article_attributes['article'] )

    if params.group_id
      group  = App.Group.find( params.group_id )

    # create article
    if sender.name is 'Customer'
      params['article'] = {
        to:                       (group && group.name) || ''
        from:                     params.customer_id_autocompletion
        subject:                  params.subject
        body:                     params.body
        ticket_article_type_id:   type.id
        ticket_article_sender_id: sender.id
        form_id:                  @form_id
      }
    else
      params['article'] = {
        from:                     (group && group.name) || ''
        to:                       params.customer_id_autocompletion
        subject:                  params.subject
        body:                     params.body
        ticket_article_type_id:   type.id
        ticket_article_sender_id: sender.id
        form_id:                  @form_id
      }

    object.load(params)

    # validate form
    errors = object.validate()

    # show errors in form
    if errors
      @log 'error', errors
      @formValidate( form: e.target, errors: errors )

    # save ticket, create article
    else

      # disable form
      @formDisable(e)
      ui = @
      object.save(
        success: ->

          # notify UI
          ui.notify
            type:    'success',
            msg:     App.i18n.translateInline( 'Ticket %s created!', @number ),
            link:    "#ticket/zoom/#{@id}"
            timeout: 12000,

          # close ticket create task
          App.TaskManager.remove( ui.task_key )

          # scroll to top
          ui.scrollTo()

          # access to group
          session = App.Session.all()
          if session && session['group_ids'] && _.contains(session['group_ids'], @group_id)
            ui.navigate "#ticket/zoom/#{@id}"
            return

          # if not, show start screen
          ui.navigate "#"


        error: ->
          ui.log 'save failed!'
          ui.formEnable(e)
      )


class UserNew extends App.ControllerModal
  constructor: ->
    super
    @render()

  render: ->

    @html App.view('agent_user_create')( head: 'New User' )

    new App.ControllerForm(
      el: @el.find('#form-user'),
      model: App.User,
      required: 'quick',
      autofocus: true,
    )

    @modalShow()

  submit: (e) ->

    e.preventDefault()
    params = @formParam(e.target)

    # if no login is given, use emails as fallback
    if !params.login && params.email
      params.login = params.email

    user = new App.User

    # find role_id
    role = App.Role.findByAttribute( 'name', 'Customer' )
    params.role_ids = role.id
    @log 'notice', 'updateAttributes', params
    user.load(params)

    errors = user.validate()
    if errors
      @log 'error', errors
      @formValidate( form: e.target, errors: errors )
      return

    # save user
    ui = @
    user.save(
      success: ->

        # force to reload object
        callbackReload = (user) ->
          realname = user.displayName()
          ui.create_screen.el.find('[name=customer_id]').val( user.id )
          ui.create_screen.el.find('[name=customer_id_autocompletion]').val( realname )

          # start customer info controller
          ui.userInfo( user_id: user.id )
          ui.modalHide()
        App.User.retrieve( @id, callbackReload , true )

      error: ->
        ui.modalHide()
    )

class TicketCreateRouter extends App.ControllerPermanent
  constructor: (params) ->
    super

    # create new uniq form id
    if !params['id']
      # remember split info if exists
      split = ''
      if params['ticket_id'] && params['article_id']
        split = "/#{params['ticket_id']}/#{params['article_id']}"

      id = Math.floor( Math.random() * 99999 )
      @navigate "#ticket_create/#{params['type']}/id/#{id}#{split}" 
      return

    # cleanup params
    clean_params =
      ticket_id:  params.ticket_id
      article_id: params.article_id
      type:       params.type
      id:         params.id

    App.TaskManager.add( 'TicketCreateScreen-' + params['type'] + '-' + params['id'], 'TicketCreate', clean_params )

# create new ticket routs/controller
App.Config.set( 'ticket_create', TicketCreateRouter, 'Routes' )
App.Config.set( 'ticket_create/:type', TicketCreateRouter, 'Routes' )
App.Config.set( 'ticket_create/:type/id/:id', TicketCreateRouter, 'Routes' )


# split ticket
App.Config.set( 'ticket_create/:type/:ticket_id/:article_id', TicketCreateRouter, 'Routes' )
App.Config.set( 'ticket_create/:type/id/:id/:ticket_id/:article_id', TicketCreateRouter, 'Routes' )

# set new task actions
App.Config.set( 'TicketNewCallOutbound', { prio: 8001, name: 'Call Outbound', target: '#ticket_create/call_outbound', role: ['Agent'] }, 'TaskActions' )
App.Config.set( 'TicketNewCallInbound', { prio: 8002, name: 'Call Inbound', target: '#ticket_create/call_inbound', role: ['Agent'] }, 'TaskActions' )
App.Config.set( 'TicketNewEmail', { prio: 8003, name: 'Email', target: '#ticket_create/email', role: ['Agent'] }, 'TaskActions' )

