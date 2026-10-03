class AddLockableToUsers < ActiveRecord::Migration[7.1]
  # Enables Devise's :lockable module. The unlock_instructions mailer
  # view (app/views/devise/mailer/unlock_instructions.html.erb) already
  # existed in this codebase before this change - just never wired up,
  # since :lockable was never added to User's devise modules and these
  # columns never existed.
  def change
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime

    add_index :users, :unlock_token, unique: true
  end
end
