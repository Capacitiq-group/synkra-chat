# Every action here is admin-only by design - billing is not
# something agents should be able to see or change. record is the
# SynkraSubscription class itself (check_authorization passes the
# class, not an instance), so this never touches @record.
class SynkraSubscriptionPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def checkout?
    @account_user.administrator?
  end

  def change_plan?
    @account_user.administrator?
  end

  def cancel?
    @account_user.administrator?
  end

  def resume?
    @account_user.administrator?
  end

  # Covers ExtraStorageController#create and ExtraSeatsController#create
  # (both authorize against this SynkraSubscription policy under the
  # 'create' action name) - missing this caused 'not authorized' errors
  # when purchasing extra storage/seats, since Pundit denies by default
  # when no matching *_? method is defined.
  def create?
    @account_user.administrator?
  end

  # StudentVerificationsController#confirm (show?/create? above cover
  # its other two actions).
  def confirm?
    @account_user.administrator?
  end

  # StudentVerificationsController#document (document route). Community
  # applications use show?/create?/update? (update? added here).
  def document?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end
end
