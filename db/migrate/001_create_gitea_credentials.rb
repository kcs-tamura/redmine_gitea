# frozen_string_literal: true

class CreateGiteaCredentials < ActiveRecord::Migration[6.1]
  def change
    create_table :gitea_credentials do |t|
      t.references :repository, null: false, index: { unique: true }
      t.text :webhook_secret
      t.timestamps null: false
    end
  end
end
