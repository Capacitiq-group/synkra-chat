class AddEmailVerifiedAtToContacts < ActiveRecord::Migration[7.2]
  def change
    add_column :contacts, :email_verified_at, :datetime
  end
end
