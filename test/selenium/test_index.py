
def test_index(s):
    s.get('http://localhost:29013/')
    assert 'Apparatus' in s.title
    assert s.find_element_by_css_selector('h1')


def test_index_2(s):
    s.get('http://localhost:29013/')
    assert 'Apparatus' in s.title
    assert s.find_element_by_css_selector('ol')
