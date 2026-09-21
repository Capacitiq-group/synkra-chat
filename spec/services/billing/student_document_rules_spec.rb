require 'rails_helper'

RSpec.describe Billing::StudentDocumentRules do
  let(:now) { Time.find_zone('Africa/Johannesburg').local(2026, 9, 22) }
  let(:facts) do
    {
      'document_type' => 'registration', 'institution_name' => 'University of Example',
      'student_full_name' => 'DLAMINI Refilwe', 'issue_date' => '2026-02-10', 'academic_year' => 2026,
      'shows_current_enrolment' => true, 'has_institution_branding' => true, 'appears_altered' => false
    }
  end

  def check(overrides = {}, name: 'Refilwe Dlamini')
    described_class.check(facts.merge(overrides), account_name: name, now: now)
  end

  it 'passes a complete, current document with the same name in any order' do
    expect(check).to eq([])
  end

  it 'ignores accents and case in names' do
    expect(check({ 'student_full_name' => 'Refilwe Dlámini' }, name: 'refilwe dlamini')).to eq([])
  end

  it 'flags a name that is not the account name' do
    expect(check({ 'student_full_name' => 'Refilwe Nomsa Dlamini' })).to include('name_mismatch')
  end

  it 'flags documents from a previous year' do
    expect(check({ 'issue_date' => '2025-03-01' })).to include('not_current_year')
  end

  it 'does not accept a student card as primary proof' do
    expect(check({ 'document_type' => 'student_card' })).to include('student_card_not_accepted')
  end

  it 'flags altered documents and missing branding' do
    result = check({ 'appears_altered' => true, 'has_institution_branding' => false })
    expect(result).to include('possible_alteration', 'branding_missing')
  end

  it 'flags everything when nothing could be read' do
    expect(described_class.check(nil, account_name: 'A B', now: now)).not_to be_empty
  end
end
