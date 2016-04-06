class CreateAsUserTest < ActionDispatch::IntegrationTest


  setup do
    @user = User.find_by_username('jdupond')
    login_as(@user, scope: :user)
  end

  test "user takes a subscription" do
    plan = Plan.find_by(group_id: @user.group.id, type: 'Plan', base_name: 'Mensuel')

    VCR.use_cassette("subscriptions_user_create_success") do
      post '/api/subscriptions',
           {
             subscription: {
               plan_id: plan.id,
               user_id: @user.id,
               card_token: stripe_card_token
             }
           }.to_json, default_headers
    end

    # Check response format & status
    assert_equal 201, response.status, response.body
    assert_equal Mime::JSON, response.content_type

    # Check the correct plan was subscribed
    subscription = json_response(response.body)
    assert_equal plan.id, subscription[:plan_id], 'subscribed plan does not match'

    # Check that the user has the correct subscription
    assert_not_nil @user.subscription, "user's subscription was not found"
    assert_not_nil @user.subscription.plan, "user's subscribed plan was not found"
    assert_equal plan.id, @user.subscription.plan_id, "user's plan does not match"

    # Check that the training credits were set correctly
    assert_empty @user.training_credits, 'training credits were not reset'
    assert_equal @user.subscription.plan.training_credit_nb, plan.training_credit_nb, 'trainings credits were not allocated'

    # Check that the user benefit from prices of his plan
    printer = Machine.find_by_slug('imprimante-3d')
    assert_equal 15, (printer.prices.find_by(group_id: @user.group_id, plan_id: @user.subscription.plan_id).amount / 100), 'machine hourly price does not match'

    # Check notifications were sent for every admins
    notifications = Notification.where(notification_type_id: NotificationType.find_by_name('notify_admin_subscribed_plan'), attached_object_type: 'Subscription', attached_object_id: subscription[:id])
    assert_not_empty notifications, 'no notifications were created'
    notified_users_ids = notifications.map {|n| n.receiver_id }
    User.admins.each do |adm|
      assert_includes notified_users_ids, adm.id, "Admin #{adm.id} was not notified"
    end

    # Check generated invoice
    invoice = Invoice.find_by(invoiced_type: 'Subscription', invoiced_id: subscription[:id])
    assert_not_nil invoice, 'Invoice was not created'
    assert File.exist?(invoice.file), 'Invoice PDF was not generated'
    assert_equal plan.amount, invoice.total, 'Invoice total price does not match the bought subscription'
  end

end