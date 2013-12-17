def test_not_found(s):
    s.get('http://localhost:29013/some_random_page')
    h1 = s.find_element_by_css_selector('h1')
    assert h1.text == 'Not Found'
